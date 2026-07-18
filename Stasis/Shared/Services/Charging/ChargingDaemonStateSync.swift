import Foundation

/// Observable cache of the daemon-owned state the app renders: the settings
/// groups, the latest snapshot, and the capabilities it carries. Payload
/// decoding and connection handling stay with the owner; this type only
/// stores confirmed values.
@MainActor
@Observable
final class ChargingDaemonStateSync {
  private(set) var chargingManagementSettings: ChargingManagementSettings?
  private(set) var chargingThresholdSettings: ChargingThresholdSettings?
  private(set) var automaticDischargeSettings: AutomaticDischargeSettings?
  private(set) var sleepPreventionSettings: SleepPreventionSettings?
  private(set) var heatProtectionSettings: HeatProtectionSettings?
  private(set) var magSafeLEDSettings: MagSafeLEDSettings?
  private(set) var batteryPercentageSettings: BatteryPercentageSettings?
  private(set) var capabilities: DaemonCapabilities?
  private(set) var daemonSnapshot: DaemonSnapshot?

  var hasLoadedAllSettings: Bool {
    chargingManagementSettings != nil
      && chargingThresholdSettings != nil
      && automaticDischargeSettings != nil
      && sleepPreventionSettings != nil
      && heatProtectionSettings != nil
      && magSafeLEDSettings != nil
      && batteryPercentageSettings != nil
  }

  /// Drops the cached settings for a new connection. The last snapshot is
  /// kept: its freshness is gated by the snapshot authority, and battery
  /// rendering may still use it as a stale fallback.
  func clearSettings() {
    chargingManagementSettings = nil
    chargingThresholdSettings = nil
    automaticDischargeSettings = nil
    sleepPreventionSettings = nil
    heatProtectionSettings = nil
    magSafeLEDSettings = nil
    batteryPercentageSettings = nil
  }

  func apply(_ bundle: DaemonSettingsBundle) {
    chargingManagementSettings = bundle.management
    chargingThresholdSettings = bundle.threshold
    automaticDischargeSettings = bundle.automaticDischarge
    sleepPreventionSettings = bundle.sleepPrevention
    heatProtectionSettings = bundle.heatProtection
    magSafeLEDSettings = bundle.magSafeLED
    batteryPercentageSettings = bundle.batteryPercentage
  }

  func applySnapshot(_ snapshot: DaemonSnapshot) {
    daemonSnapshot = snapshot
    if capabilities != snapshot.capabilities {
      capabilities = snapshot.capabilities
    }
  }

  func apply(_ settings: ChargingManagementSettings) {
    chargingManagementSettings = settings
  }

  func apply(_ settings: ChargingThresholdSettings) {
    chargingThresholdSettings = settings
  }

  func apply(_ settings: AutomaticDischargeSettings) {
    automaticDischargeSettings = settings
  }

  func apply(_ settings: SleepPreventionSettings) {
    sleepPreventionSettings = settings
  }

  func apply(_ settings: HeatProtectionSettings) {
    heatProtectionSettings = settings
  }

  func apply(_ settings: MagSafeLEDSettings) {
    magSafeLEDSettings = settings
  }

  func apply(_ settings: BatteryPercentageSettings) {
    batteryPercentageSettings = settings
  }
}
