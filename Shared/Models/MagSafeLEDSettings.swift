import Foundation

nonisolated struct MagSafeLEDSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool = true
    var heatProtectionState: MagSafeLEDState = .blinkOrangeSlow
}
