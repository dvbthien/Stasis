import Foundation

/// Every persisted settings group in one payload. Returned by the daemon's
/// `getAllSettings` command so clients can hydrate their caches with a single
/// round-trip instead of one request per group.
struct DaemonSettingsBundle: Codable, Equatable, Sendable {
    let management: ChargingManagementSettings
    let threshold: ChargingThresholdSettings
    let automaticDischarge: AutomaticDischargeSettings
    let sleepPrevention: SleepPreventionSettings
    let heatProtection: HeatProtectionSettings
    let magSafeLED: MagSafeLEDSettings
    let batteryPercentage: BatteryPercentageSettings
}
