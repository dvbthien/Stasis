import Foundation

/// Canonical charging settings exchanged between Stasis and its daemon.
///
/// Validation and persistence intentionally remain for a later migration
/// phase. Keeping this as a plain value now lets policy code stop depending on
/// app-only `Defaults` while preserving the current runtime behavior.
struct DaemonSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var managementEnabled: Bool
    var chargeLimit: Int
    var useHardwarePercentage: Bool

    var sailingModeEnabled: Bool
    var sailingDelta: Int
    var automaticDischarge: Bool

    var preventSleepUntilLimit: Bool

    var heatProtectionEnabled: Bool
    var heatProtectionLimit: Int

    var manageMagSafeLED: Bool
    var heatProtectionLEDStateRawValue: UInt8

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        managementEnabled: Bool = false,
        chargeLimit: Int = 80,
        useHardwarePercentage: Bool = false,
        sailingModeEnabled: Bool = true,
        sailingDelta: Int = 5,
        automaticDischarge: Bool = true,
        preventSleepUntilLimit: Bool = false,
        heatProtectionEnabled: Bool = true,
        heatProtectionLimit: Int = 40,
        manageMagSafeLED: Bool = true,
        heatProtectionLEDStateRawValue: UInt8 = 6
    ) {
        self.schemaVersion = schemaVersion
        self.managementEnabled = managementEnabled
        self.chargeLimit = chargeLimit
        self.useHardwarePercentage = useHardwarePercentage
        self.sailingModeEnabled = sailingModeEnabled
        self.sailingDelta = sailingDelta
        self.automaticDischarge = automaticDischarge
        self.preventSleepUntilLimit = preventSleepUntilLimit
        self.heatProtectionEnabled = heatProtectionEnabled
        self.heatProtectionLimit = heatProtectionLimit
        self.manageMagSafeLED = manageMagSafeLED
        self.heatProtectionLEDStateRawValue = heatProtectionLEDStateRawValue
    }
}
