import Foundation

struct DeviceCapabilities: Sendable, Equatable {
    let chargingControl: Bool
    let adapterControl: Bool
    let hasMagSafe: Bool
    let magsafeLEDControl: Bool

    static let unknown = DeviceCapabilities(
        chargingControl: false,
        adapterControl: false,
        hasMagSafe: false,
        magsafeLEDControl: false
    )
}
