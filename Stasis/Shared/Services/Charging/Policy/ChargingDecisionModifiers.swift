import Foundation
import smc_power

/// Overrides charging off — and the MagSafe LED, if managed — whenever the
/// battery is running hot, regardless of what `ChargeLimitPolicy` decided.
/// Applied after the base decision since heat protection always wins.
enum HeatProtectionPolicy {
    static func apply(
        to decision: inout ChargingDecision,
        controlState: BatteryControlState,
        settings: ChargingSettingsSnapshot
    ) {
        guard settings.heatProtectionEnabled,
            controlState.batteryTemperature > Double(settings.heatProtectionLimit)
        else { return }

        decision.desiredCharging = false
        decision.reason = "Battery temperature exceeds \(settings.heatProtectionLimit)°C"
        if settings.manageMagSafeLED {
            decision.desiredLED = settings.heatProtectionMagSafeLEDState
        }
    }
}

/// Forces charging and the adapter off when the user has manually requested
/// a discharge cycle, overriding any other policy's decision.
enum ForceDischargePolicy {
    static func apply(to decision: inout ChargingDecision, isActive: Bool) {
        guard isActive else { return }
        decision.desiredCharging = false
        decision.desiredAdapter = false
    }
}
