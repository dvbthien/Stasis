import Foundation

/// Errors surfaced by any XPC-backed service call (charging helper, SMC
/// reader). Centralized here so both `BatteryService` and future XPC
/// clients can throw/catch the same type instead of each defining their own.
enum XPCError: LocalizedError {
    case helperUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "XPC helper is unavailable"
        case .commandFailed(let message):
            "Command failed: \(message)"
        }
    }
}

/// Installation state of the privileged charging-control daemon, as reported
/// by `SMAppService`.
enum ChargingHelperStatus {
    case notInstalled
    case requiresApproval
    case installed
}
