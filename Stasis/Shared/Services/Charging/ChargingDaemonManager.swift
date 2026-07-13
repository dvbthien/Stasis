import Foundation
import ServiceManagement
import os.log

@MainActor
@Observable
class ChargingDaemonManager {
  static let shared = ChargingDaemonManager()

  private static let machServiceName = "com.srimanachanta.stasis-daemon"
  private static let plistName = "com.srimanachanta.stasis-daemon.plist"
  private static let commandTimeout: Duration = .seconds(8)

  private let service: SMAppService
  private var connection: NSXPCConnection?
  @ObservationIgnored private lazy var callbackReceiver = ChargingDaemonCallbackReceiver(
    stateDidChange: { [weak self] payload in
      Task { @MainActor in
        self?.receiveSnapshot(payload)
      }
    },
    settingsDidChange: { [weak self] payload in
      Task { @MainActor in
        self?.receiveSettings(payload)
      }
    }
  )

  private let logger = Logger.stasis("ChargingDaemonManager")

  private(set) var helperStatus: ChargingHelperStatus
  private(set) var connectionStatus: ChargingDaemonConnectionStatus = .disconnected
  private(set) var daemonSettingsState: DaemonSettingsState?
  private(set) var daemonSnapshot: DaemonSnapshot?

  var isInstalled: Bool {
    service.status == .enabled
  }

  private init() {
    service = SMAppService.daemon(plistName: Self.plistName)
    switch service.status {
    case .enabled: helperStatus = .installed
    case .requiresApproval: helperStatus = .requiresApproval
    default: helperStatus = .notInstalled
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

  func uninstall() throws {
    logger.info("Unregistering charging daemon")
    disconnect()
    try service.unregister()
    helperStatus = .notInstalled
  }

  func repairInstallation() async throws {
    logger.info("Repairing charging daemon registration")
    disconnect()

    // A running helper can be from an older app build. Re-registering the
    // daemon asks launchd to use the helper bundled with the current app.
    if service.status == .enabled {
      try await service.unregister()
      try await Task.sleep(for: .milliseconds(500))
    }

    try install()
  }

  func refreshStatus() {
    switch service.status {
    case .enabled: helperStatus = .installed
    case .requiresApproval: helperStatus = .requiresApproval
    default: helperStatus = .notInstalled
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
  }

  func setTelemetryActive(_ active: Bool) async throws {
    try await executeCommand(active ? "Enable daemon telemetry" : "Disable daemon telemetry") {
      helper, reply in
      helper.setTelemetryActive(active) { success in
        reply(success, success ? nil : "Daemon rejected telemetry demand")
      }
    }
  }

  func synchronizeChargingSettings(_ settings: DaemonSettings) async throws -> DaemonSettingsState {
    let payload = try DaemonPayloadCodec.encode(settings)
    try await executeCommand("Synchronize daemon charging settings") { [weak self] helper, reply in
      helper.setSettings(authData: nil, payload: payload) { response, errorMessage in
        Task { @MainActor in
          guard let response else {
            reply(false, errorMessage ?? "Daemon rejected charging settings")
            return
          }
          do {
            self?.daemonSettingsState = try DaemonPayloadCodec.decode(
              DaemonSettingsState.self,
              from: response
            )
            reply(true, nil)
          } catch {
            reply(false, "Invalid daemon settings response: \(error.localizedDescription)")
          }
        }
      }
    }
    guard let daemonSettingsState else {
      throw XPCError.commandFailed("Daemon did not return canonical charging settings")
    }
    return daemonSettingsState
  }

  func setChargeLimitOverride(_ enabled: Bool) async throws {
    try await executeCommand("Set charge-limit override") { [weak self] helper, reply in
      helper.setChargeLimitOverride(enabled: enabled) { response, errorMessage in
        Task { @MainActor in
          self?.handleSnapshotCommandResponse(
            response,
            errorMessage: errorMessage,
            reply: reply
          )
        }
      }
    }
  }

  func setForceDischarge(_ enabled: Bool) async throws {
    try await executeCommand("Set force discharge") { [weak self] helper, reply in
      helper.setForceDischarge(authData: nil, enabled: enabled) { response, errorMessage in
        Task { @MainActor in
          self?.handleSnapshotCommandResponse(
            response,
            errorMessage: errorMessage,
            reply: reply
          )
        }
      }
    }
  }

  func getHelper(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingDaemonProtocol? {
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
    try await executeCommand("Verify charging daemon") { helper, reply in
      helper.checkHealth { payload, errorMessage in
        Task { @MainActor in
          guard let payload else {
            reply(false, errorMessage ?? "Charging daemon did not respond")
            return
          }
          do {
            _ = try DaemonPayloadCodec.decode(DaemonHealth.self, from: payload)
            reply(true, nil)
          } catch {
            reply(false, "Invalid daemon health response: \(error.localizedDescription)")
          }
        }
      }
    }
  }

  func recordRuntimeError(_ error: Error, while label: String) {
    let message = "\(label) failed: \(error.localizedDescription)"
    logger.error("\(message)")
    connectionStatus = .runtimeFailed(message)
  }

  private func connect() {
    connectionStatus = .connecting
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
    newConnection.exportedObject = callbackReceiver

    newConnection.invalidationHandler = { [weak self, weak newConnection] in
      Task { @MainActor in
        guard let self else { return }
        self.logger.warning("Charging daemon XPC connection invalidated")
        if self.connection === newConnection {
          self.connection = nil
          self.connectionStatus = .invalidated
        }
      }
    }

    newConnection.interruptionHandler = { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.connectionStatus = .interrupted
        self.logger.warning(
          "Charging daemon XPC connection interrupted; keeping connection for automatic recovery")
      }
    }

    newConnection.resume()
    connection = newConnection
    synchronizeInitialState()
  }

  func disconnect() {
    invalidateActiveConnection()
    connectionStatus = .disconnected
  }

  private func invalidateActiveConnection() {
    guard let activeConnection = connection else {
      return
    }
    connection = nil
    activeConnection.invalidate()
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
      let helper = getHelper(errorHandler: { [weak self] error in
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
        connectionStatus = failureStatus(message: "Helper unavailable")
        continuation.resume(throwing: XPCError.helperUnavailable)
      }
      return
    }

    operation(helper) { [weak self] success, errorMessage in
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

  private func synchronizeInitialState() {
    guard
      let helper = getHelper(errorHandler: { [weak self] error in
        Task { @MainActor in
          self?.recordRuntimeError(error, while: "Initial daemon settings sync")
        }
      })
    else { return }

    helper.getSettings { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self else { return }
        guard let payload else {
          self.connectionStatus = .runtimeFailed(
            errorMessage ?? "Daemon did not return settings"
          )
          return
        }

        do {
          let state = try DaemonPayloadCodec.decode(DaemonSettingsState.self, from: payload)
          if state.needsLegacyImport {
            self.importLegacySettings()
          } else {
            self.daemonSettingsState = state
            self.requestInitialSnapshot()
          }
        } catch {
          self.recordRuntimeError(error, while: "Decode daemon settings")
        }
      }
    }
  }

  private func importLegacySettings() {
    guard
      let payload = try? DaemonPayloadCodec.encode(DaemonSettings.currentAppDefaults),
      let helper = getHelper(errorHandler: { [weak self] error in
        Task { @MainActor in
          self?.recordRuntimeError(error, while: "Legacy settings import")
        }
      })
    else { return }

    helper.importLegacySettings(payload: payload) { [weak self] response, errorMessage in
      Task { @MainActor in
        guard let self else { return }
        guard let response else {
          self.connectionStatus = .runtimeFailed(
            errorMessage ?? "Daemon rejected legacy settings import"
          )
          return
        }
        do {
          self.daemonSettingsState = try DaemonPayloadCodec.decode(
            DaemonSettingsState.self,
            from: response
          )
          self.requestInitialSnapshot()
        } catch {
          self.recordRuntimeError(error, while: "Decode imported daemon settings")
        }
      }
    }
  }

  private func requestInitialSnapshot() {
    guard
      let helper = getHelper(errorHandler: { [weak self] error in
        Task { @MainActor in
          self?.recordRuntimeError(error, while: "Initial daemon snapshot sync")
        }
      })
    else { return }

    helper.getSnapshot { [weak self] payload, errorMessage in
      Task { @MainActor in
        guard let self else { return }
        guard let payload else {
          self.connectionStatus = .runtimeFailed(
            errorMessage ?? "Daemon did not return a snapshot"
          )
          return
        }
        self.receiveSnapshot(payload)
        self.connectionStatus = .connected
      }
    }
  }

  private func receiveSettings(_ payload: Data) {
    do {
      daemonSettingsState = try DaemonPayloadCodec.decode(
        DaemonSettingsState.self,
        from: payload
      )
    } catch {
      recordRuntimeError(error, while: "Decode daemon settings callback")
    }
  }

  private func receiveSnapshot(_ payload: Data) {
    do {
      daemonSnapshot = try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload)
      // A valid callback also proves that an interrupted XPC connection has
      // recovered. This switches BatteryService back from its local fallback.
      connectionStatus = .connected
    } catch {
      recordRuntimeError(error, while: "Decode daemon snapshot callback")
    }
  }

  private func handleSnapshotCommandResponse(
    _ payload: Data?,
    errorMessage: String?,
    reply: @escaping @Sendable (Bool, String?) -> Void
  ) {
    guard let payload else {
      reply(false, errorMessage ?? "Daemon did not return an updated snapshot")
      return
    }
    do {
      daemonSnapshot = try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload)
      reply(true, nil)
    } catch {
      reply(false, "Invalid daemon snapshot response: \(error.localizedDescription)")
    }
  }
}

nonisolated final class ChargingDaemonCallbackReceiver: NSObject, ChargingDaemonClientProtocol,
  @unchecked Sendable
{
  private let stateDidChangeHandler: @Sendable (Data) -> Void
  private let settingsDidChangeHandler: @Sendable (Data) -> Void

  init(
    stateDidChange: @escaping @Sendable (Data) -> Void,
    settingsDidChange: @escaping @Sendable (Data) -> Void
  ) {
    stateDidChangeHandler = stateDidChange
    settingsDidChangeHandler = settingsDidChange
  }

  nonisolated func stateDidChange(_ payload: Data) {
    stateDidChangeHandler(payload)
  }

  nonisolated func settingsDidChange(_ payload: Data) {
    settingsDidChangeHandler(payload)
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
