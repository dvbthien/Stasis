import Foundation

nonisolated struct ChargingThresholdSettings: Codable, Equatable, Sendable {
    var chargeLimit: Int = 80
    var sailingModeEnabled: Bool = true
    var sailingDelta: Int = 5
}
