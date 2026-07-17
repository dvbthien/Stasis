import Foundation

/// Errors surfaced by any XPC-backed service call (charging daemon, SMC
/// reader). Centralized here so both `BatteryService` and future XPC
/// clients can throw/catch the same type instead of each defining their own.
enum XPCError: LocalizedError {
  case serviceUnavailable
  case commandFailed(String)
  case timedOut(String)

  var errorDescription: String? {
    switch self {
    case .serviceUnavailable:
      "XPC service is unavailable"
    case .commandFailed(let message):
      "Command failed: \(message)"
    case .timedOut(let message):
      message
    }
  }
}

/// Installation state of the privileged charging-control daemon, as reported
/// by `SMAppService`.
enum ChargingDaemonStatus: Equatable {
  case notInstalled
  case requiresApproval
  case installed
}

/// Runtime state of the app's XPC connection to the charging-control daemon.
enum ChargingDaemonConnectionStatus: Equatable {
  case disconnected
  case connecting
  case connected
  case interrupted
  case invalidated
  case startupFailed(String)
  case runtimeFailed(String)
}
