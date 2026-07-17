enum ChargingServiceSemanticStatus: Equatable {
    case checking
    case ready
    case needsApproval
    case notInstalled
    case connectionIssue
}

enum ChargingServiceRecoveryAction: Equatable {
    case tryAgain
    case reconnect
}

struct ChargingServiceStatusPresentation: Equatable {
    let status: ChargingServiceSemanticStatus
    let recoveryAction: ChargingServiceRecoveryAction?
    let canRemoveService: Bool

    init(
        daemonStatus: ChargingDaemonStatus,
        connectionStatus: ChargingDaemonConnectionStatus,
        isDeterminingStatus: Bool,
        hasOperationError: Bool
    ) {
        if isDeterminingStatus {
            status = .checking
            recoveryAction = nil
            canRemoveService = false
            return
        }

        switch daemonStatus {
        case .notInstalled:
            status = .notInstalled
            recoveryAction = hasOperationError ? .tryAgain : nil
            canRemoveService = false
        case .requiresApproval:
            status = .needsApproval
            recoveryAction = nil
            canRemoveService = false
        case .installed:
            switch connectionStatus {
            case .connecting:
                status = .checking
                recoveryAction = nil
                canRemoveService = false
            case .connected:
                status = .ready
                recoveryAction = hasOperationError ? .tryAgain : nil
                canRemoveService = true
            case .startupFailed:
                status = .connectionIssue
                recoveryAction = .tryAgain
                canRemoveService = false
            case .disconnected, .interrupted, .invalidated, .runtimeFailed:
                status = .connectionIssue
                recoveryAction = .reconnect
                canRemoveService = false
            }
        }
    }
}
