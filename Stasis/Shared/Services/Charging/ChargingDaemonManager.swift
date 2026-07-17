import Foundation
import ServiceManagement
import os.log

@MainActor
private final class ChargingSettingsCommandResult<Value> {
  var value: Value?

  @inline(never)
  deinit {}
}

@MainActor
@Observable
class ChargingDaemonManager {
  static let shared = ChargingDaemonManager()

  private static let machServiceName = Constants.Identity.daemon
  private static let plistName = Constants.Identity.daemonPlistName
  private static let commandTimeout: Duration = .seconds(8)

  private let service: SMAppService
  private var connection: NSXPCConnection?
  @ObservationIgnored private var callbackReceiver: ChargingDaemonCallbackReceiver?
  private var snapshotAuthority = ChargingDaemonSnapshotAuthority()

  private let logger = Logger.stasis("ChargingDaemonManager")

  private(set) var daemonStatus: ChargingDaemonStatus
  private(set) var connectionStatus: ChargingDaemonConnectionStatus = .disconnected
  private(set) var chargingManagementSettings: ChargingManagementSettings?
  private(set) var chargingThresholdSettings: ChargingThresholdSettings?
  private(set) var automaticDischargeSettings: AutomaticDischargeSettings?
  private(set) var sleepPreventionSettings: SleepPreventionSettings?
  private(set) var heatProtectionSettings: HeatProtectionSettings?
  private(set) var magSafeLEDSettings: MagSafeLEDSettings?
  private(set) var batteryPercentageSettings: BatteryPercentageSettings?
  private(set) var capabilities: DaemonCapabilities?
  private(set) var daemonSnapshot: DaemonSnapshot?
  @ObservationIgnored private(set) var daemonExecutableHash: String?
  @ObservationIgnored private var outdatedRepairTask: Task<Bool, Error>?
  @ObservationIgnored private var didScheduleStartupBuildCheck = false
  @ObservationIgnored private lazy var bundledDaemonExecutableHash: String? =
    DaemonBuildIdentity.executableHash(
      at: Bundle.main.bundleURL
        .appendingPathComponent(Constants.Identity.daemonExecutableBundlePath)
    )

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
    snapshotAuthority.isAuthoritative && daemonSnapshot != nil
  }

  var isInstalled: Bool {
    service.status == .enabled
  }

  private init() {
    service = SMAppService.daemon(plistName: Self.plistName)
    switch service.status {
    case .enabled: daemonStatus = .installed
    case .requiresApproval: daemonStatus = .requiresApproval
    default: daemonStatus = .notInstalled
    }
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
      try await executeCommand("Prepare charging daemon for uninstall") { daemon, reply in
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
      try await executeCommand("Cancel charging daemon uninstall preparation") { daemon, reply in
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
    if connection == nil {
      connect()
    }
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
    try await executeCommand("Set charging management settings") { [weak self] daemon, reply in
      daemon.setChargingManagementSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { self?.chargingManagementSettings = $0 }
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
    try await executeCommand("Set charging threshold settings") { [weak self] daemon, reply in
      daemon.setChargingThresholdSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { confirmed in
            self?.chargingThresholdSettings = confirmed
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
    try await executeCommand("Set automatic discharge settings") { [weak self] daemon, reply in
      daemon.setAutomaticDischargeSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { self?.automaticDischargeSettings = $0 }
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
    try await executeCommand("Set sleep prevention settings") { [weak self] daemon, reply in
      daemon.setSleepPreventionSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { self?.sleepPreventionSettings = $0 }
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
    try await executeCommand("Set heat protection settings") { [weak self] daemon, reply in
      daemon.setHeatProtectionSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { confirmed in
            self?.heatProtectionSettings = confirmed
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
    try await executeCommand("Set MagSafe LED settings") { [weak self] daemon, reply in
      daemon.setMagSafeLEDSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { self?.magSafeLEDSettings = $0 }
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
    try await executeCommand("Set battery percentage settings") { [weak self] daemon, reply in
      daemon.setBatteryPercentageSettings(payload: payload) { response, error in
        Task { @MainActor in
          Self.decodeSettingsResponse(response, error: error, reply: reply) { self?.batteryPercentageSettings = $0 }
        }
      }
    }
    guard let batteryPercentageSettings else { throw XPCError.commandFailed("Missing percentage settings response") }
    return batteryPercentageSettings
  }

  func setChargeLimitOverride(_ enabled: Bool) async throws {
    try await executeCommand("Set charge-limit override") { [weak self] daemon, reply in
      let generation = self?.snapshotAuthority.generation
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
    try await executeCommand("Set force discharge") { [weak self] daemon, reply in
      let generation = self?.snapshotAuthority.generation
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

  func getDaemon(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingDaemonProtocol? {
    if connection == nil {
      connect()
    }
    guard let connection else { return nil }
    return connection.remoteObjectProxyWithErrorHandler(errorHandler)
      as? ChargingDaemonProtocol
  }

  func executeCommand(
    _ label: String,
    operation:
      @escaping @MainActor (
        ChargingDaemonProtocol,
        @escaping @Sendable (Bool, String?) -> Void
      ) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      let context = ChargingDaemonCommandContext()
      context.timeoutTask = scheduleTimeout(
        label,
        context: context,
        continuation: continuation
      )
      executeCommandAttempt(
        label,
        retryOnRemoteError: true,
        context: context,
        continuation: continuation,
        operation: operation
      )
    }
  }

  func verifyConnection() async throws {
    // Keep verification side-effect free. Capability-specific SMC commands
    // can fail even when the daemon is reachable.
    try await executeCommand("Verify charging daemon") { daemon, reply in
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
    for _ in 0..<160 {
      if chargingManagementSettings != nil,
        chargingThresholdSettings != nil,
        automaticDischargeSettings != nil,
        sleepPreventionSettings != nil,
        heatProtectionSettings != nil,
        magSafeLEDSettings != nil,
        batteryPercentageSettings != nil
      {
        return
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw XPCError.timedOut("Charging daemon did not finish loading settings.")
  }

  func recordRuntimeError(_ error: Error, while label: String) {
    let message = "\(label) failed: \(error.localizedDescription)"
    logger.error("\(message)")
    connectionStatus = .runtimeFailed(message)
  }

  private func connect() {
    connectionStatus = .connecting
    daemonExecutableHash = nil
    chargingManagementSettings = nil
    chargingThresholdSettings = nil
    automaticDischargeSettings = nil
    sleepPreventionSettings = nil
    heatProtectionSettings = nil
    magSafeLEDSettings = nil
    batteryPercentageSettings = nil
    let generation = snapshotAuthority.beginConnection()
    logger.info("Setting up XPC connection to charging daemon")
    let newConnection = NSXPCConnection(
      machServiceName: Self.machServiceName
    )
    newConnection.remoteObjectInterface = NSXPCInterface(
      with: ChargingDaemonProtocol.self
    )
    newConnection.exportedInterface = NSXPCInterface(
      with: ChargingDaemonClientProtocol.self
    )
    let receiver = makeSnapshotCallbackReceiver(for: generation)
    callbackReceiver = receiver
    newConnection.exportedObject = receiver

    newConnection.invalidationHandler = { [weak self, weak newConnection] in
      Task { @MainActor in
        guard let self else { return }
        self.logger.warning("Charging daemon XPC connection invalidated")
        if self.connection === newConnection, self.snapshotAuthority.isCurrent(generation) {
          self.connection = nil
          self.callbackReceiver = nil
          self.snapshotAuthority.invalidate(generation)
          self.connectionStatus = .invalidated
        }
      }
    }

    newConnection.interruptionHandler = { [weak self, weak newConnection] in
      Task { @MainActor in
        guard let self,
          self.connection === newConnection,
          self.snapshotAuthority.isCurrent(generation)
        else { return }
        self.snapshotAuthority.revoke(generation)
        self.connectionStatus = .interrupted
        self.logger.warning(
          "Charging daemon XPC connection interrupted; keeping connection for automatic recovery")
      }
    }

    newConnection.resume()
    connection = newConnection
    requestInitialDaemonState(generation: generation)
  }

  func disconnect() {
    invalidateActiveConnection()
    connectionStatus = .disconnected
  }

  private func invalidateActiveConnection() {
    let activeConnection = connection
    connection = nil
    callbackReceiver = nil
    snapshotAuthority.invalidateCurrentGeneration()
    activeConnection?.invalidate()
  }

  private func executeCommandAttempt(
    _ label: String,
    retryOnRemoteError: Bool,
    context: ChargingDaemonCommandContext,
    continuation: CheckedContinuation<Void, any Error>,
    operation:
      @escaping @MainActor (
        ChargingDaemonProtocol,
        @escaping @Sendable (Bool, String?) -> Void
      ) -> Void
  ) {
    let attempt = context.beginAttempt()
    guard
      let daemon = getDaemon(errorHandler: { [weak self] error in
        Task { @MainActor in
          guard let self, context.shouldHandle(attempt) else { return }
          self.logger.error(
            "charging daemon XPC error while \(label): \(error.localizedDescription)")

          // Match Battery Toolkit's behavior: keep one cached
          // connection, but retry once after invalidating it when
          // XPC reports a stale or broken remote object.
          if retryOnRemoteError {
            self.logger.info("Retrying charging daemon command after XPC error: \(label)")
            self.connectionStatus = self.failureStatus(message: error.localizedDescription)
            self.disconnect()
            self.executeCommandAttempt(
              label,
              retryOnRemoteError: false,
              context: context,
              continuation: continuation,
              operation: operation
            )
          } else if context.complete(attempt) {
            context.cancelTimeout()
            self.connectionStatus = self.failureStatus(message: error.localizedDescription)
            continuation.resume(throwing: XPCError.commandFailed(error.localizedDescription))
          }
        }
      })
    else {
      if context.complete(attempt) {
        context.cancelTimeout()
        connectionStatus = failureStatus(message: "Daemon unavailable")
        continuation.resume(throwing: XPCError.serviceUnavailable)
      }
      return
    }

    operation(daemon) { [weak self] success, errorMessage in
      Task { @MainActor in
        guard context.complete(attempt) else { return }
        context.cancelTimeout()
        if success {
          self?.connectionStatus = .connected
          continuation.resume()
        } else {
          let message = errorMessage ?? "Unknown error"
          self?.connectionStatus = self?.failureStatus(message: message) ?? .runtimeFailed(message)
          continuation.resume(throwing: XPCError.commandFailed(message))
        }
      }
    }
  }

  private func scheduleTimeout(
    _ label: String,
    context: ChargingDaemonCommandContext,
    continuation: CheckedContinuation<Void, any Error>
  ) -> Task<Void, Never> {
    Task {
      try? await Task.sleep(for: Self.commandTimeout)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard context.timeout() else { return }
        let message = "Charging daemon did not respond while \(label)."
        logger.error("\(message)")
        connectionStatus = failureStatus(message: message)
        invalidateActiveConnection()
        continuation.resume(throwing: XPCError.timedOut(message))
      }
    }
  }

  private func failureStatus(message: String) -> ChargingDaemonConnectionStatus {
    switch connectionStatus {
    case .connected, .interrupted, .invalidated:
      .runtimeFailed(message)
    case .disconnected, .connecting, .startupFailed, .runtimeFailed:
      .startupFailed(message)
    }
  }

  private func isActiveConnection(_ generation: UInt64) -> Bool {
    snapshotAuthority.isCurrent(generation) && connection != nil
  }

  private func makeSnapshotCallbackReceiver(for generation: UInt64) -> ChargingDaemonCallbackReceiver {
    ChargingDaemonCallbackReceiver(
      stateDidChange: { [weak self] payload in
        Task { @MainActor in
          self?.handleSnapshotPayload(payload, generation: generation)
        }
      }
    )
  }

  private func requestInitialDaemonState(generation: UInt64) {
    guard
      let daemon = getDaemon(errorHandler: { [weak self] error in
        Task { @MainActor in
          guard let self, self.isActiveConnection(generation) else { return }
          self.recordRuntimeError(error, while: "Initial daemon settings sync")
        }
      })
    else { return }

    requestSettingsGroup(generation: generation, getter: daemon.getChargingManagementSettings) {
      self.chargingManagementSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getChargingThresholdSettings) {
      self.chargingThresholdSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getAutomaticDischargeSettings) {
      self.automaticDischargeSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getSleepPreventionSettings) {
      self.sleepPreventionSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getHeatProtectionSettings) {
      self.heatProtectionSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getMagSafeLEDSettings) {
      self.magSafeLEDSettings = $0
    }
    requestSettingsGroup(generation: generation, getter: daemon.getBatteryPercentageSettings) {
      self.batteryPercentageSettings = $0
    }
    requestDaemonSnapshot(generation: generation)
  }

  private func requestSettingsGroup<Value: Decodable & Sendable>(
    generation: UInt64,
    getter: (@escaping @Sendable (Data?, String?) -> Void) -> Void,
    assign: @escaping @MainActor (Value) -> Void
  ) {
    getter { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self, self.isActiveConnection(generation) else { return }
        guard let payload else {
          self.connectionStatus = .runtimeFailed(errorMessage ?? "Daemon did not return settings")
          return
        }
        do {
          assign(try DaemonPayloadCodec.decode(Value.self, from: payload))
        } catch {
          self.recordRuntimeError(error, while: "Decode daemon settings")
        }
      }
    }
  }

  private func requestDaemonSnapshot(generation: UInt64) {
    guard
      let daemon = getDaemon(errorHandler: { [weak self] error in
        Task { @MainActor in
          guard let self, self.isActiveConnection(generation) else { return }
          self.recordRuntimeError(error, while: "Initial daemon snapshot sync")
        }
      })
    else { return }

    daemon.getSnapshot { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self, self.isActiveConnection(generation) else { return }
        guard let payload else {
          self.connectionStatus = .runtimeFailed(
            errorMessage ?? "Daemon did not return a snapshot"
          )
          return
        }
        self.handleSnapshotPayload(payload, generation: generation)
      }
    }
  }

  private func handleSnapshotPayload(_ payload: Data, generation: UInt64) {
    guard isActiveConnection(generation) else { return }
    do {
      let recoveredFromInterruption = connectionStatus == .interrupted
      applySnapshot(try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload))
      snapshotAuthority.markAuthoritative(generation)
      // A valid callback also proves that an interrupted XPC connection has
      // recovered. This switches BatteryService back from its local fallback.
      connectionStatus = .connected
      if recoveredFromInterruption {
        requestInitialDaemonState(generation: generation)
      }
    } catch {
      recordRuntimeError(error, while: "Decode daemon snapshot callback")
    }
  }

  private func applySnapshot(_ snapshot: DaemonSnapshot) {
    daemonSnapshot = snapshot
    if capabilities != snapshot.capabilities {
      capabilities = snapshot.capabilities
    }
  }

  private func handleSnapshotCommandPayload(
    _ payload: Data?,
    errorMessage: String?,
    generation: UInt64?,
    reply: @escaping @Sendable (Bool, String?) -> Void
  ) {
    guard let generation, isActiveConnection(generation) else {
      reply(false, "Charging daemon connection changed before the command completed")
      return
    }
    guard let payload else {
      reply(false, errorMessage ?? "Daemon did not return an updated snapshot")
      return
    }
    do {
      applySnapshot(try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload))
      snapshotAuthority.markAuthoritative(generation)
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

struct ChargingDaemonSnapshotAuthority {
  private(set) var generation: UInt64 = 0
  private(set) var authoritativeGeneration: UInt64?

  var isAuthoritative: Bool {
    authoritativeGeneration == generation
  }

  mutating func beginConnection() -> UInt64 {
    generation &+= 1
    authoritativeGeneration = nil
    return generation
  }

  func isCurrent(_ candidate: UInt64) -> Bool {
    candidate == generation
  }

  mutating func markAuthoritative(_ candidate: UInt64) {
    guard isCurrent(candidate) else { return }
    authoritativeGeneration = candidate
  }

  mutating func revoke(_ candidate: UInt64) {
    guard isCurrent(candidate) else { return }
    authoritativeGeneration = nil
  }

  mutating func invalidate(_ candidate: UInt64) {
    guard isCurrent(candidate) else { return }
    invalidateCurrentGeneration()
  }

  mutating func invalidateCurrentGeneration() {
    generation &+= 1
    authoritativeGeneration = nil
  }
}

nonisolated final class ChargingDaemonCallbackReceiver: NSObject, ChargingDaemonClientProtocol,
  @unchecked Sendable
{
  private let stateDidChangeHandler: @Sendable (Data) -> Void

  init(stateDidChange: @escaping @Sendable (Data) -> Void) {
    stateDidChangeHandler = stateDidChange
  }

  nonisolated func stateDidChange(_ payload: Data) {
    stateDidChangeHandler(payload)
  }
}

@MainActor
private final class ChargingDaemonCommandContext {
  var timeoutTask: Task<Void, Never>?

  private var activeAttempt = 0
  private var completed = false

  func beginAttempt() -> Int {
    activeAttempt += 1
    return activeAttempt
  }

  func shouldHandle(_ attempt: Int) -> Bool {
    !completed && activeAttempt == attempt
  }

  func complete(_ attempt: Int) -> Bool {
    guard shouldHandle(attempt) else { return false }
    completed = true
    return true
  }

  func timeout() -> Bool {
    guard !completed else { return false }
    completed = true
    return true
  }

  func cancelTimeout() {
    timeoutTask?.cancel()
    timeoutTask = nil
  }
}
