import Foundation

struct DaemonHealth: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var status: DaemonRuntimeStatus
    var daemonVersion: String
    var chargeControlMode: ChargeControlMode
    // Optional so payloads from daemons built before this field decode.
    var executableHash: String?
}
