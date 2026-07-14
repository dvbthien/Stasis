import Foundation

nonisolated enum MagSafeLEDState: UInt8, Codable, Sendable {
    case reset = 0
    case off = 1
    case green = 3
    case orange = 4
    case blinkOrangeSlow = 6
    case blinkOrangeFast = 7
}
