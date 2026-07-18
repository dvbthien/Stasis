import Foundation
import ServiceManagement
import os.log

@MainActor
private final class ChargingSettingsCommandResult<Value> {
  var value: Value?

  @inline(never)
  deinit {}
}

/// Facade over the charging daemon: SMAppService lifecycle (install/
/// uninstall/repair), build-identity checks, and the typed settings and
/// command API. Connection handling lives in `ChargingDaemonTransport`;
/// cached daemon state lives in `ChargingDaemonStateSync`.
@MainActor
@Observable
class ChargingDaemonManager {
  static let shared = ChargingDaemonManager()

  private static let machServiceName = Constants.Identity.daemon
  private static let plistName = Constants.Identity.daemonPlistName

  private let service: SMAppService
  private let transport: ChargingDaemonTransport
  private let stateSync = ChargingDaemonStateSync()

  private let logger = Logger.stasis("ChargingDaemonManager")

  private(set) var daemonStatus: ChargingDaemonStatus
  @ObservationIgnored private(set) var daemonExecutableHash: String?
  @ObservationIgnored private var outdatedRepairTask: Task<Bool, Error>?
  @ObservationIgnored private var didScheduleStartupBuildCheck = false
  @ObservationIgnored private lazy var bundledDaemonExecutableHash: String? =
    DaemonBuildIdentity.executableHash(
      at: Bundle.main.bundleURL
        .appendingPathComponent(Constants.Identity.daemonExecutableBundlePath)
    )

  var connectionStatus: ChargingDaemonConnectionStatus { transport.connectionStatus }
  var chargingManagementSettings: ChargingManagementSettings? { stateSync.chargingManagementSettings }
  var chargingThresholdSettings: ChargingThresholdSettings? { stateSync.chargingThresholdSettings }
  var automaticDischargeSettings: AutomaticDischargeSettings? { stateSync.automaticDischargeSettings }
  var sleepPreventionSettings: SleepPreventionSettings? { stateSync.sleepPreventionSettings }
  var heatProtectionSettings: HeatProtectionSettings? { stateSync.heatProtectionSettings }
  var magSafeLEDSettings: MagSafeLEDSettings? { stateSync.magSafeLEDSettings }
  var batteryPercentageSettings: BatteryPercentageSettings? { stateSync.batteryPercentageSettings }
  var capabilities: DaemonCapabilities? { stateSync.capabilities }
  var daemonSnapshot: DaemonSnapshot? { stateSync.daemonSnapshot }
  var settingsBundle: DaemonSettingsBundle? { stateSync.settingsBundle }

  /// True when the connected daemon was spawned from a different binary than
  /// the one bundled with this app, meaning launchd is still running an older
  /// build and the registration should be repaired.
  var isDaemonOutdated: Bool {
    guard
      let daemonExecutableHash,
      let bundledDaemonExecutableHash
    else { return false }
    return daemonExecutableHash != bundledDaemonExecutableHash
  }

  var hasFreshDaemonSnapshot: Bool {
    transport.isAuthoritative && stateSync.daemonSnapshot != nil
  }

  var isInstalled: Bool {
    service.status == .enabled
  }

  private init() {
    service = SMAppService.daemon(plistName: Self.plistName)
    transport = ChargingDaemonTransport(machServiceName: Self.machServiceName)
    switch service.status {
    case .enabled: daemonStatus = .installed
    case .requiresApproval: daemonStatus = .requiresApproval
    default: daemonStatus = .notInstalled
    }
    transport.delegate = self
  }

  func install() throws {
    logger.info("Registering charging daemon")

    do {
      try service.register()
    } catch {
      // register() commonly throws "Operation not permitted" while macOS
      // processes the background item notification, even though the
      // registration advanced to requiresApproval or enabled.
      if service.status != .enabled && service.status != .requiresApproval {
        throw error
      }
    }

    refreshStatus()
  }

  func uninstall() async throws {
    logger.info("Unregistering charging daemon")
    var preparedDaemon = false
    if service.status == .enabled {
      if chargingManagementSettings?.isEnabled == true {
        _ = try await setChargingManagementSettings(.init(isEnabled: false))
      }
      try await transport.executeCommand("Prepare charging daemon for uninstall") { daemon, reply in
        daemon.prepareForUninstall(authData: nil, reply: reply)
      }
      preparedDaemon = true
    }

    // Drop our XPC connection first so it doesn't keep the daemon alive
    // while launchd tears the job down. If unregister fails, the rollback
    // command below reconnects on demand.
    disconnect()

    do {
      try await service.unregister()
    } catch {
      if preparedDaemon {
        await cancelUninstallPreparationAfterFailure()
      }
      throw error
    }
    daemonStatus = .notInstalled
  }

  private func cancelUninstallPreparationAfterFailure() async {
    do {
      try await transport.executeCommand("Cancel charging daemon uninstall preparation") { daemon, reply in
        daemon.cancelUninstallPreparation { success in
          reply(success, success ? nil : "Daemon rejected uninstall cancellation")
        }
      }
    } catch {
      logger.error(
        "Could not resume charging management after uninstall failed: \(error.localizedDescription)"
      )
    }
  }

  func repairInstallation() async throws {
    logger.info("Repairing charging daemon registration")
    disconnect()

    // A running daemon can be from an older app build. Re-registering the
    // daemon asks launchd to use the daemon bundled with the current app.
    if service.status == .enabled {
      try await service.unregister()
      try await Task.sleep(for: .milliseconds(500))
    }

    try install()
  }

  func refreshStatus() {
    switch service.status {
    case .enabled: daemonStatus = .installed
    case .requiresApproval: daemonStatus = .requiresApproval
    default: daemonStatus = .notInstalled
    }
  }

  /// Starts the long-lived state callback connection when the daemon is
  /// available. Battery rendering uses this independently of charging
  /// management being enabled in Settings.
  func startStateStreaming() {
    refreshStatus()
    guard service.status == .enabled else { return }
    transport.connectIfNeeded()
    scheduleStartupBuildCheck()
  }

  /// Verifies the connected daemon's build identity and re-registers the
  /// daemon when it was spawned from a different binary than the one bundled
  /// with this app. Single-flight: concurrent callers share one repair.
  /// Returns true when a repair was performed.
  func repairDaemonIfOutdated() async throws -> Bool {
    if let outdatedRepairTask {
      return try await outdatedRepairTask.value
    }
    let task = Task<Bool, Error> {
      defer { outdatedRepairTask = nil }
      try await verifyConnection()
      guard isDaemonOutdated else { return false }
      logger.info(
        "Charging daemon binary differs from the bundled build; repairing to update it"
      )
      try await repairInstallation()
      try await verifyConnection()
      return true
    }
    outdatedRepairTask = task
    return try await task.value
  }

  private func scheduleStartupBuildCheck() {
    guard !didScheduleStartupBuildCheck else { return }
    didScheduleStartupBuildCheck = true
    Task { [weak self] in
      guard let self else { return }
      do {
        if try await repairDaemonIfOutdated() {
          logger.info("Replaced outdated charging daemon at startup")
        }
      } catch {
        logger.error(
          "Startup charging daemon build check failed: \(error.localizedDescription)"
        )
      }
    }
  }

  func setChargingManagementSettings(
    _ settings: ChargingManagementSettings
  ) async throws -> ChargingManagementSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await transport.executeCommand("Set charging management settings") { [weak self] daemon, reply in
      daemon.setChargingManagementSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: ChargingManagementSettings) in self?.stateSync.apply(confirmed)
          }
        }
      }
    }
    guard let chargingManagementSettings else { throw XPCError.commandFailed("Missing management settings response") }
    return chargingManagementSettings
  }

  func setChargingThresholdSettings(
    _ settings: ChargingThresholdSettings
  ) async throws -> ChargingThresholdSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    let result = ChargingSettingsCommandResult<ChargingThresholdSettings>()
    try await transport.executeCommand("Set charging threshold settings") { [weak self] daemon, reply in
      daemon.setChargingThresholdSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: ChargingThresholdSettings) in
            self?.stateSync.apply(confirmed)
            result.value = confirmed
          }
        }
      }
    }
    guard let confirmed = result.value else {
      throw XPCError.commandFailed("Missing threshold settings response")
    }
    return confirmed
  }

  func setAutomaticDischargeSettings(
    _ settings: AutomaticDischargeSettings
  ) async throws -> AutomaticDischargeSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await transport.executeCommand("Set automatic discharge settings") { [weak self] daemon, reply in
      daemon.setAutomaticDischargeSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: AutomaticDischargeSettings) in self?.stateSync.apply(confirmed)
          }
        }
      }
    }
    guard let automaticDischargeSettings else { throw XPCError.commandFailed("Missing discharge settings response") }
    return automaticDischargeSettings
  }

  func setSleepPreventionSettings(
    _ settings: SleepPreventionSettings
  ) async throws -> SleepPreventionSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await transport.executeCommand("Set sleep prevention settings") { [weak self] daemon, reply in
      daemon.setSleepPreventionSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: SleepPreventionSettings) in self?.stateSync.apply(confirmed)
          }
        }
      }
    }
    guard let sleepPreventionSettings else { throw XPCError.commandFailed("Missing sleep settings response") }
    return sleepPreventionSettings
  }

  func setHeatProtectionSettings(
    _ settings: HeatProtectionSettings
  ) async throws -> HeatProtectionSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    let result = ChargingSettingsCommandResult<HeatProtectionSettings>()
    try await transport.executeCommand("Set heat protection settings") { [weak self] daemon, reply in
      daemon.setHeatProtectionSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: HeatProtectionSettings) in
            self?.stateSync.apply(confirmed)
            result.value = confirmed
          }
        }
      }
    }
    guard let confirmed = result.value else {
      throw XPCError.commandFailed("Missing heat settings response")
    }
    return confirmed
  }

  func setMagSafeLEDSettings(
    _ settings: MagSafeLEDSettings
  ) async throws -> MagSafeLEDSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await transport.executeCommand("Set MagSafe LED settings") { [weak self] daemon, reply in
      daemon.setMagSafeLEDSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: MagSafeLEDSettings) in self?.stateSync.apply(confirmed)
          }
        }
      }
    }
    guard let magSafeLEDSettings else { throw XPCError.commandFailed("Missing MagSafe settings response") }
    return magSafeLEDSettings
  }

  func setBatteryPercentageSettings(
    _ settings: BatteryPercentageSettings
  ) async throws -> BatteryPercentageSettings {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await transport.executeCommand("Set battery percentage settings") { [weak self] daemon, reply in
      daemon.setBatteryPercentageSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) {
            (confirmed: BatteryPercentageSettings) in self?.stateSync.apply(confirmed)
          }
        }
      }
    }
    guard let batteryPercentageSettings else { throw XPCError.commandFailed("Missing percentage settings response") }
    return batteryPercentageSettings
  }

  func setChargeLimitOverride(_ enabled: Bool) async throws {
    try await transport.executeCommand("Set charge-limit override") { [weak self] daemon, reply in
      let generation = self?.transport.currentGeneration
      daemon.setChargeLimitOverride(enabled: enabled) { response, errorMessage in
        Task { @MainActor in
          self?.handleSnapshotCommandPayload(
            response,
            errorMessage: errorMessage,
            generation: generation,
            reply: reply
          )
        }
      }
    }
  }

  func setForceDischarge(_ enabled: Bool) async throws {
    try await transport.executeCommand("Set force discharge") { [weak self] daemon, reply in
      let generation = self?.transport.currentGeneration
      daemon.setForceDischarge(authData: nil, enabled: enabled) { response, errorMessage in
        Task { @MainActor in
          self?.handleSnapshotCommandPayload(
            response,
            errorMessage: errorMessage,
            generation: generation,
            reply: reply
          )
        }
      }
    }
  }

  func verifyConnection() async throws {
    // Keep verification side-effect free. Capability-specific SMC commands
    // can fail even when the daemon is reachable.
    try await transport.executeCommand("Verify charging daemon") { daemon, reply in
      daemon.checkHealth { payload, errorMessage in
        Task { @MainActor [weak self] in
          guard let payload else {
            reply(false, errorMessage ?? "Charging daemon did not respond")
            return
          }
          do {
            let health = try DaemonPayloadCodec.decode(DaemonHealth.self, from: payload)
            self?.daemonExecutableHash = health.executableHash
            reply(true, nil)
          } catch {
            reply(false, "Invalid daemon health response: \(error.localizedDescription)")
          }
        }
      }
    }
    try await syncAllSettings()
  }

  /// Loads every settings group with a single `getAllSettings` round-trip and
  /// hydrates the cache before returning.
  func syncAllSettings() async throws {
    try await transport.executeCommand("Load charging daemon settings") { [weak self] daemon, reply in
      let generation = self?.transport.currentGeneration
      daemon.getAllSettings { payload, errorMessage in
        Task { @MainActor in
          guard
            let self, let generation,
            self.transport.isActiveConnection(generation)
          else {
            reply(false, "Charging daemon connection changed before settings loaded")
            return
          }
          guard let payload else {
            reply(false, errorMessage ?? "Daemon did not return settings")
            return
          }
          do {
            self.stateSync.apply(
              try DaemonPayloadCodec.decode(DaemonSettingsBundle.self, from: payload)
            )
            reply(true, nil)
          } catch {
            reply(false, "Invalid daemon settings response: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  func recordRuntimeError(_ error: Error, while label: String) {
    let message = "\(label) failed: \(error.localizedDescription)"
    logger.error("\(message)")
    transport.recordRuntimeFailure(message)
  }

  func disconnect() {
    transport.disconnect()
  }

  private func requestInitialDaemonState(generation: UInt64) {
    guard
      let daemon = transport.getDaemon(errorHandler: { [weak self] error in
        Task { @MainActor in
          guard let self, self.transport.isActiveConnection(generation) else { return }
          self.recordRuntimeError(error, while: "Initial daemon state sync")
        }
      })
    else { return }

    daemon.getAllSettings { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self, self.transport.isActiveConnection(generation) else { return }
        guard let payload else {
          self.transport.recordRuntimeFailure(errorMessage ?? "Daemon did not return settings")
          return
        }
        do {
          self.stateSync.apply(
            try DaemonPayloadCodec.decode(DaemonSettingsBundle.self, from: payload)
          )
        } catch {
          self.recordRuntimeError(error, while: "Decode daemon settings")
        }
      }
    }

    daemon.getSnapshot { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self, self.transport.isActiveConnection(generation) else { return }
        guard let payload else {
          self.transport.recordRuntimeFailure(
            errorMessage ?? "Daemon did not return a snapshot"
          )
          return
        }
        self.handleSnapshotPayload(payload, generation: generation)
      }
    }
  }

  private func handleSnapshotPayload(_ payload: Data, generation: UInt64) {
    guard transport.isActiveConnection(generation) else { return }
    do {
      let recoveredFromInterruption = transport.connectionStatus == .interrupted
      stateSync.applySnapshot(try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload))
      transport.markAuthoritative(generation)
      // A valid callback also proves that an interrupted XPC connection has
      // recovered. This switches BatteryService back from its local fallback.
      transport.markConnected()
      if recoveredFromInterruption {
        requestInitialDaemonState(generation: generation)
      }
    } catch {
      recordRuntimeError(error, while: "Decode daemon snapshot callback")
    }
  }

  private func handleSnapshotCommandPayload(
    _ payload: Data?,
    errorMessage: String?,
    generation: UInt64?,
    reply: @escaping @Sendable (Bool, String?) -> Void
  ) {
    guard let generation, transport.isActiveConnection(generation) else {
      reply(false, "Charging daemon connection changed before the command completed")
      return
    }
    guard let payload else {
      reply(false, errorMessage ?? "Daemon did not return an updated snapshot")
      return
    }
    do {
      stateSync.applySnapshot(try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload))
      transport.markAuthoritative(generation)
      reply(true, nil)
    } catch {
      reply(false, "Invalid daemon snapshot response: \(error.localizedDescription)")
    }
  }

  private static func decodeSettingsResponse<Value: Decodable & Sendable>(
    _ payload: Data?,
    error: String?,
    reply: @escaping @Sendable (Bool, String?) -> Void,
    assign: (Value) -> Void
  ) {
    guard let payload else {
      reply(false, error ?? "Daemon rejected settings")
      return
    }
    do {
      assign(try DaemonPayloadCodec.decode(Value.self, from: payload))
      reply(true, nil)
    } catch {
      reply(false, "Invalid daemon settings response: \(error.localizedDescription)")
    }
  }
}

extension ChargingDaemonManager: ChargingDaemonTransportDelegate {
  func transportWillConnect() {
    daemonExecutableHash = nil
    stateSync.clearSettings()
  }

  func transportDidConnect(generation: UInt64) {
    requestInitialDaemonState(generation: generation)
  }

  func transport(didReceiveSnapshot payload: Data, generation: UInt64) {
    handleSnapshotPayload(payload, generation: generation)
  }
}
