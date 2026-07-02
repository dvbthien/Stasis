import Defaults
import smc_power

/// A single, consistent read of every `Defaults` value the charging policy
/// needs for one evaluation pass.
///
/// `ChargingCoordinator.evaluate` used to read `Defaults[...]` directly from
/// inside deeply nested conditionals — over a dozen call sites scattered
/// through one function. Reading everything up front, once, into a plain
/// struct means the policy functions take a single, easy-to-pass parameter
/// instead of reaching back into global state, which is also what makes
/// them straightforward to unit test in isolation.
struct ChargingSettingsSnapshot {
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

    /// - Parameter chargeLimitOverrideActive: when the user has temporarily
    ///   overridden the charge limit to top up to 100%, owned by
    ///   `ChargingCoordinator` rather than `Defaults` since it's a transient,
    ///   in-memory toggle rather than a persisted setting.
    init(chargeLimitOverrideActive: Bool) {
        chargeLimit = chargeLimitOverrideActive ? 100 : Defaults[.chargeLimit]
        useHardwarePercentage = Defaults[.useHardwarePercentage]

        sailingModeEnabled = Defaults[.sailingMode]
        sailingModeLimit = Defaults[.sailingModeLimit]
        automaticDischarge = Defaults[.automaticDischarge]

        manageMagSafeLED = Defaults[.manageMagSafeLED]

        heatProtectionEnabled = Defaults[.enableHeatProtectionMode]
        heatProtectionLimit = Defaults[.heatProtectionLimit]
        heatProtectionMagSafeLEDState = Defaults[.heatProtectionMagSafeLEDState]

        disableSleepUntilChargeLimit = Defaults[.disableSleepUntilChargeLimit]
    }

    /// The percentage to evaluate policy against — hardware or
    /// display-smoothed, per user preference.
    func batteryPercentage(for controlState: BatteryControlState) -> Int {
        useHardwarePercentage
            ? controlState.hardwareBatteryPercentage
            : controlState.batteryPercentage
    }
}
