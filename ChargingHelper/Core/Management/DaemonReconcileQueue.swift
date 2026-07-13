import Foundation

enum DaemonPolicyEvent: String, Hashable, Sendable {
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

struct DaemonPolicyReconcileResult: Sendable, Equatable {
    let powerPathChanged: Bool
    let shouldPublishSnapshot: Bool

    static let publishSnapshot = DaemonPolicyReconcileResult(
        powerPathChanged: false,
        shouldPublishSnapshot: true
    )
    static let publishAfterPowerPathChange = DaemonPolicyReconcileResult(
        powerPathChanged: true,
        shouldPublishSnapshot: true
    )
    static let noPublication = DaemonPolicyReconcileResult(
        powerPathChanged: false,
        shouldPublishSnapshot: false
    )
}

/// Coalesces explicit policy events and guarantees that only one reconciliation
/// applies hardware changes at a time. This queue owns no periodic task.
actor DaemonReconcileQueue {
    typealias Operation = @Sendable (Set<DaemonPolicyEvent>) async -> DaemonPolicyReconcileResult

    private var pendingEvents: Set<DaemonPolicyEvent> = []
    private var pendingWaiters: [CheckedContinuation<DaemonPolicyReconcileResult, Never>] = []
    private var isRunning = false
    private var operation: Operation?
    private var retryTask: Task<Void, Never>?

    func start(operation: @escaping Operation) {
        guard self.operation == nil else { return }
        self.operation = operation
    }

    func request(_ event: DaemonPolicyEvent) async -> DaemonPolicyReconcileResult {
        await withCheckedContinuation { continuation in
            guard operation != nil else {
                continuation.resume(returning: .noPublication)
                return
            }

            pendingEvents.insert(event)
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
        pendingEvents.removeAll()
        let waiters = pendingWaiters
        pendingWaiters.removeAll()
        operation = nil
        waiters.forEach { $0.resume(returning: .noPublication) }
    }

    private func finishRetryDelay() async {
        retryTask = nil
        _ = await request(.retry)
    }

    private func drainPendingRequests() async {
        while !pendingEvents.isEmpty, let operation {
            let events = pendingEvents
            let waiters = pendingWaiters
            pendingEvents.removeAll()
            pendingWaiters.removeAll()

            let result = await operation(events)
            waiters.forEach { $0.resume(returning: result) }
        }
        isRunning = false
    }
}
