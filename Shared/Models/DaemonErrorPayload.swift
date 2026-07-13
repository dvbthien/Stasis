import Foundation

enum DaemonErrorCode: String, Codable, Sendable {
    case invalidPayload
    case incompatibleSchema
    case unsupported
    case unauthorized
    case smcFailure
    case persistenceFailure
    case internalFailure
}

/// Codable error information suitable for state snapshots and XPC replies.
struct DaemonErrorPayload: Codable, Equatable, Error, Sendable {
    let code: DaemonErrorCode
    let message: String
}
