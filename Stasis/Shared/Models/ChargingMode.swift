enum ChargingMode: Equatable {
    case charging
    case discharging
    case pluggedIn

    /// Single source of truth for the state glyph shown by both the AppKit
    /// renderer and the SwiftUI indicator views.
    var symbolName: String? {
        switch self {
        case .charging: "bolt.fill"
        case .pluggedIn: "powerplug.portrait.fill"
        case .discharging: nil
        }
    }
}
