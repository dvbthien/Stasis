import Foundation

/// Hardware capabilities reported by the daemon to its clients.
///
/// Mode-dependent values are derived instead of serialized independently, so
/// a decoded payload cannot claim that direct charging control is available in
/// firmware mode.
struct DaemonCapabilities: Codable, Equatable, Sendable {
    let chargeControlMode: ChargeControlMode
    let adapterControl: Bool
    let magSafeLEDKeyAvailable: Bool

    var chargingControl: Bool {
        chargeControlMode != .unsupported
    }

    var directChargingControl: Bool {
        chargeControlMode == .legacy
    }

    var firmwareChargeLimitControl: Bool {
        chargeControlMode == .firmware
    }

    var sailingModeControl: Bool {
        chargingControl
    }

    var automaticDischargeControl: Bool {
        directChargingControl && adapterControl
    }

    var forceDischargeControl: Bool {
        chargingControl && adapterControl
    }

    var chargeLimitOverrideControl: Bool {
        chargingControl
    }

    var sleepHooks: Bool {
        chargeControlMode == .legacy
    }

    var heatProtectionControl: Bool {
        directChargingControl
    }

    var magSafeLEDControl: Bool {
        directChargingControl && magSafeLEDKeyAvailable
    }
}
