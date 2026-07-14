import Foundation

nonisolated struct BatteryPercentageSettings: Codable, Equatable, Sendable {
    var useHardwarePercentage: Bool = false
}
