import Foundation

/// Versioned XPC surface for the daemon migration.
///
/// All structured values travel as encoded `Data`, so both XPC interfaces only
/// use Foundation classes and need no custom allowed-class configuration.
/// Primitive SMC methods remain temporarily for app-policy compatibility and
/// are removed after policy ownership moves to the daemon.
@objc protocol ChargingDaemonProtocol {
    func checkHealth(reply: @escaping @Sendable (Data?, String?) -> Void)
    func getSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void)
    func getSettings(reply: @escaping @Sendable (Data?, String?) -> Void)

    func setSettings(
        authData: Data?,
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func importLegacySettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func setChargeLimitOverride(
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func setForceDischarge(
        authData: Data?,
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    )

    func setTelemetryActive(
        _ active: Bool,
        reply: @escaping @Sendable (Bool) -> Void
    )

    func manageBatteryCharging(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func manageExternalPower(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    func manageMagsafeLED(
        target: UInt8,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
}
