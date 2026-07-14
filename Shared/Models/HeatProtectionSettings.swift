import Foundation

nonisolated struct HeatProtectionSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool = true
    var temperatureLimit: Int = 40
}
