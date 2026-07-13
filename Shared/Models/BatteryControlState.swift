import Foundation

/// Minimal, target-independent input consumed by the charging policy.
struct BatteryControlState: Equatable, Sendable {
    var batteryPercentage: Int = 0
    var hardwareBatteryPercentage: Int = 0
    var adapterConnected: Bool = false
    var batteryTemperature: Double = 0
}
