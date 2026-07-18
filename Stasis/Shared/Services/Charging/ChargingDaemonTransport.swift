import Foundation
import os.log

/// Connection-lifecycle events the owner reacts to. State caching stays out of
/// the transport: it only reports payloads and connection boundaries.
@MainActor
protocol ChargingDaemonTransportDelegate: AnyObject {
  /// A new connection is about to be set up, so any cached daemon state is stale.
  func transportWillConnect()
  /// A connection was resumed and the initial daemon state should be requested.
  func transportDidConnect(generation: UInt64)
  /// The daemon pushed a state snapshot over the callback channel.
  func transport(didReceiveSnapshot payload: Data, generation: UInt64)
}

/// Owns the XPC connection to the charging daemon: setup/teardown, the
/// invalidation/interruption handlers, command execution with retry and
/// timeout, and the generation-based snapshot authority that guards against
/// stale callbacks after a reconnect.
@MainActor
@Observable
final class ChargingDaemonTransport {
  private let machServiceName: String
  private let commandTimeout: Duration

  @ObservationIgnored weak var delegate: ChargingDaemonTransportDelegate?

  private(set) var connectionStatus: ChargingDaemonConnectionStatus = .disconnected
  @ObservationIgnored private var connection: NSXPCConnection?
  @ObservationIgnored private var callbackReceiver: ChargingDaemonCallbackReceiver?
  private var snapshotAuthority = ChargingDaemonSnapshotAuthority()

  private let logger = Logger.stasis("ChargingDaemonTransport")

  init(machServiceName: String, commandTimeout: Duration = .seconds(8)) {
    self.machServiceName = machServiceName
    self.commandTimeout = commandTimeout
  }

  var currentGeneration: UInt64 {
    snapshotAuthority.generation
  }

  var isAuthoritative: Bool {
    snapshotAuthority.isAuthoritative
  }

  func isActiveConnection(_ generation: UInt64) -> Bool {
    snapshotAuthority.isCurrent(generation) && connection != nil
  }

  func markAuthoritative(_ generation: UInt64) {
    snapshotAuthority.markAuthoritative(generation)
  }

  func markConnected() {
    connectionStatus = .connected
  }

  func recordRuntimeFailure(_ message: String) {
    connectionStatus = .runtimeFailed(message)
  }

  func connectIfNeeded() {
    if connection == nil {
      connect()
    }
  }

  func disconnect() {
    invalidateActiveConnection()
    connectionStatus = .disconnected
  }

  func getDaemon(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingDaemonProtocol? {
    connectIfNeeded()
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

  private func connect() {
    connectionStatus = .connecting
    delegate?.transportWillConnect()
    let generation = snapshotAuthority.beginConnection()
    logger.info("Setting up XPC connection to charging daemon")
    let newConnection = NSXPCConnection(
      machServiceName: machServiceName
    )
    newConnection.remoteObjectInterface = NSXPCInterface(
      with: ChargingDaemonProtocol.self
    )
    newConnection.exportedInterface = NSXPCInterface(
      with: ChargingDaemonClientProtocol.self
    )
    let receiver = ChargingDaemonCallbackReceiver(
      stateDidChange: { [weak self] payload in
        Task { @MainActor in
          self?.delegate?.transport(didReceiveSnapshot: payload, generation: generation)
        }
      }
    )
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
    delegate?.transportDidConnect(generation: generation)
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
      try? await Task.sleep(for: commandTimeout)
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
