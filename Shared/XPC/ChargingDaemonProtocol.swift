import Foundation

/// Versioned XPC surface for the daemon migration.
///
/// All structured values travel as encoded `Data`, so both XPC interfaces only
/// use Foundation classes and need no custom allowed-class configuration.
/// Charging policy and every SMC write remain private to the daemon.
@objc protocol ChargingDaemonProtocol {
    func checkHealth(reply: @escaping @Sendable (Data?, String?) -> Void)
    func getSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)

    /// Returns every settings group as one `DaemonSettingsBundle` payload.
    func getAllSettings(reply: @escaping @Sendable (Data?, String?) -> Void)

    func setChargingManagementSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setChargingThresholdSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setAutomaticDischargeSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setSleepPreventionSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setHeatProtectionSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setMagSafeLEDSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func setBatteryPercentageSettings(payload: Data, reply: @escaping @Sendable (Data?, String?) -> Void)

    func setChargeLimitOverride(
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func setForceDischarge(
        authData: Data?,
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func prepareForUninstall(
        authData: Data?,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func cancelUninstallPreparation(
        reply: @escaping @Sendable (Bool) -> Void
    )
}
