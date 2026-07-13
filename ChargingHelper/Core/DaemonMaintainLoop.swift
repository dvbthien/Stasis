import Foundation

enum DaemonMaintainReason: String, Hashable, Sendable {
    case startup
    case powerSource
    case settings
    case wake
    case temporaryCommand
    case hardwareCommand
    case periodic
    case retry
}

/// Coalesces triggers and guarantees that only one reconciliation is applying
/// hardware changes at a time, even while an actor call is suspended.
actor DaemonMaintainLoop {
    typealias Operation = @Sendable (Set<DaemonMaintainReason>) async -> Void

    private var pendingReasons: Set<DaemonMaintainReason> = []
    private var isRunning = false
    private var operation: Operation?
    private var periodicTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    func start(
        periodicInterval: Duration = .seconds(10),
        operation: @escaping Operation
    ) {
        guard periodicTask == nil else { return }
        self.operation = operation
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: periodicInterval)
                guard !Task.isCancelled, let self else { return }
                await self.request(.periodic)
            }
        }
    }

    func request(_ reason: DaemonMaintainReason) async {
        pendingReasons.insert(reason)
        guard !isRunning, let operation else { return }

        isRunning = true
        while !pendingReasons.isEmpty {
            let reasons = pendingReasons
            pendingReasons.removeAll()
            await operation(reasons)
        }
        isRunning = false
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
        periodicTask?.cancel()
        periodicTask = nil
        retryTask?.cancel()
        retryTask = nil
        pendingReasons.removeAll()
        operation = nil
    }

    private func finishRetryDelay() async {
        retryTask = nil
        await request(.retry)
    }
}
