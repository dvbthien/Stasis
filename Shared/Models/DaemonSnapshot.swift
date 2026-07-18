import Foundation

struct DaemonBatterySnapshot: Codable, Equatable, Sendable {
    var displayedPercentage: Int = 0
    var hardwarePercentage: Int = 0
    var isCharging: Bool = false
    var timeRemaining: Int = 0

    /// True while the machine is running on AC power (the power-source state
    /// the system battery icon reflects); false during force discharge even
    /// with the cable attached. Optional so snapshots from daemons that
    /// predate the field decode as nil and the app keeps its own IOKit value.
    var externalConnected: Bool? = nil

    /// Kept daemon-side for the heat-protection policy; other hardware
    /// readings (health, capacities, cycle count, electrical telemetry)
    /// are read directly by the app and are not part of the snapshot.
    var temperature: Double = 0
}

struct DaemonAdapterSnapshot: Codable, Equatable, Sendable {
    var physicallyConnected: Bool = false
    var powerEnabled: Bool? = nil
}

struct DaemonFirmwareChargeLimitState: Codable, Equatable, Sendable {
    var active: Bool
    var lower: Int
    var upper: Int
}

struct DaemonHardwareState: Codable, Equatable, Sendable {
    var chargingInhibited: Bool? = nil
    var forceDischarging: Bool? = nil
    var magSafeLEDStateRawValue: UInt8? = nil
    var firmwareChargeLimit: DaemonFirmwareChargeLimitState? = nil
}

struct DaemonPolicyState: Codable, Equatable, Sendable {
    var managementEnabled: Bool = false
    var chargeLimitOverrideActive: Bool = false
    var forceDischargeActive: Bool = false

    var desiredCharging: Bool? = nil
    var desiredAdapter: Bool? = nil
    var desiredLEDStateRawValue: UInt8? = nil
    var reason: String? = nil
}

enum DaemonRuntimeStatus: String, Codable, Sendable {
    case starting
    case ready
    case degraded
    case unsupported
}

struct DaemonRuntimeState: Codable, Equatable, Sendable {
    var status: DaemonRuntimeStatus = .starting
    var daemonVersion: String = ""
    var updatedAt: Date = .distantPast
    var lastError: DaemonErrorPayload? = nil
}

struct DaemonSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var capabilities: DaemonCapabilities
    var battery: DaemonBatterySnapshot
    var adapter: DaemonAdapterSnapshot
    var hardware: DaemonHardwareState
    var policy: DaemonPolicyState
    var runtime: DaemonRuntimeState
}
