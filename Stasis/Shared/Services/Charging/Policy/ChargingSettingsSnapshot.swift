import smc_power

/// Plain policy input for one evaluation pass.
///
/// This type deliberately has no dependency on app `Defaults`. The current app
/// runtime builds `DaemonSettings` through an app-only bridge, while the future
/// daemon can supply its canonical persisted settings directly.
struct ChargingSettingsSnapshot: Equatable, Sendable {
    let chargeLimit: Int
    let useHardwarePercentage: Bool

    let sailingModeEnabled: Bool
    let sailingModeLimit: Int
    let automaticDischarge: Bool

    let manageMagSafeLED: Bool

    let heatProtectionEnabled: Bool
    let heatProtectionLimit: Int
    let heatProtectionMagSafeLEDState: MagSafeLEDState

    let disableSleepUntilChargeLimit: Bool

    init(settings: DaemonSettings, chargeLimitOverrideActive: Bool) {
        chargeLimit = chargeLimitOverrideActive ? 100 : settings.chargeLimit
        useHardwarePercentage = settings.useHardwarePercentage

        sailingModeEnabled = settings.sailingModeEnabled
        sailingModeLimit = settings.sailingDelta
        automaticDischarge = settings.automaticDischarge

        manageMagSafeLED = settings.manageMagSafeLED

        heatProtectionEnabled = settings.heatProtectionEnabled
        heatProtectionLimit = settings.heatProtectionLimit
        heatProtectionMagSafeLEDState =
            MagSafeLEDState(rawValue: settings.heatProtectionLEDStateRawValue)
            ?? .blinkOrangeSlow

        disableSleepUntilChargeLimit = settings.preventSleepUntilLimit
    }

    /// The percentage to evaluate policy against — hardware or
    /// display-smoothed, per user preference.
    func batteryPercentage(for controlState: BatteryControlState) -> Int {
        useHardwarePercentage
            ? controlState.hardwareBatteryPercentage
            : controlState.batteryPercentage
    }
}
