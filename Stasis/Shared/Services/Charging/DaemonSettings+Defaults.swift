import Defaults
import smc_power

/// Temporary Phase 1 bridge that preserves the current app-owned runtime.
/// This is removed once the daemon settings store becomes authoritative.
extension DaemonSettings {
    static var currentAppDefaults: DaemonSettings {
        DaemonSettings(
            managementEnabled: Defaults[.manageCharging],
            chargeLimit: Defaults[.chargeLimit],
            useHardwarePercentage: Defaults[.useHardwarePercentage],
            sailingModeEnabled: Defaults[.sailingMode],
            sailingDelta: Defaults[.sailingModeLimit],
            automaticDischarge: Defaults[.automaticDischarge],
            preventSleepUntilLimit: Defaults[.disableSleepUntilChargeLimit],
            heatProtectionEnabled: Defaults[.enableHeatProtectionMode],
            heatProtectionLimit: Defaults[.heatProtectionLimit],
            manageMagSafeLED: Defaults[.manageMagSafeLED],
            heatProtectionLEDStateRawValue: Defaults[.heatProtectionMagSafeLEDState].rawValue
        )
    }
}
