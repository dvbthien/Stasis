import Foundation

enum DaemonMaintainReason: String, Hashable, Sendable {
    case startup
    case powerSource
    case settings
    case wake
    case temporaryCommand
    case hardwareCommand
    case uninstall
    case shutdown
    case retry
}

/// Coalesces explicit events and guarantees that only one reconciliation is
/// applying hardware changes at a time. This coordinator owns no periodic task.
actor DaemonMaintainLoop {
    typealias Operation = @Sendable (Set<DaemonMaintainReason>) async -> Void

    private var pendingReasons: Set<DaemonMaintainReason> = []
    private var pendingWaiters: [CheckedContinuation<Void, Never>] = []
    private var isRunning = false
    private var operation: Operation?
    private var retryTask: Task<Void, Never>?

    func start(operation: @escaping Operation) {
        guard self.operation == nil else { return }
        self.operation = operation
    }

    func request(_ reason: DaemonMaintainReason) async {
        await withCheckedContinuation { continuation in
            guard operation != nil else {
                continuation.resume()
                return
            }

            pendingReasons.insert(reason)
            pendingWaiters.append(continuation)
            guard !isRunning else { return }

            isRunning = true
            Task { [weak self] in
                await self?.drainPendingRequests()
            }
        }
    }

    func scheduleRetry(after delay: Duration) {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.finishRetryDelay()
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        pendingReasons.removeAll()
        let waiters = pendingWaiters
        pendingWaiters.removeAll()
        operation = nil
        waiters.forEach { $0.resume() }
    }

    private func finishRetryDelay() async {
        retryTask = nil
        await request(.retry)
    }

    private func drainPendingRequests() async {
        while !pendingReasons.isEmpty, let operation {
            let reasons = pendingReasons
            let waiters = pendingWaiters
            pendingReasons.removeAll()
            pendingWaiters.removeAll()

            await operation(reasons)
            waiters.forEach { $0.resume() }
        }
        isRunning = false
    }
}
