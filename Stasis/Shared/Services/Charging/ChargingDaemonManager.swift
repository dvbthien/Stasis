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

    private let logger = Logger.stasis("ChargingDaemonManager")

    private(set) var helperStatus: ChargingHelperStatus
    private(set) var connectionStatus: ChargingDaemonConnectionStatus = .disconnected

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

    func getHelper(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingHelperProtocol? {
        if connection == nil {
            connect()
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? ChargingHelperProtocol
    }

    func executeCommand(
        _ label: String,
        operation: @escaping @MainActor (
            ChargingHelperProtocol,
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
            helper.checkHealth { success, errorMessage in
                reply(success, success ? nil : errorMessage ?? "Charging daemon did not respond")
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
            with: ChargingHelperProtocol.self
        )

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
                self.logger.warning("Charging daemon XPC connection interrupted; keeping connection for automatic recovery")
            }
        }

        newConnection.resume()
        connection = newConnection
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
        operation: @escaping @MainActor (
            ChargingHelperProtocol,
            @escaping @Sendable (Bool, String?) -> Void
        ) -> Void
    ) {
        let attempt = context.beginAttempt()
        guard
            let helper = getHelper(errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self, context.shouldHandle(attempt) else { return }
                    self.logger.error("charging daemon XPC error while \(label): \(error.localizedDescription)")

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
