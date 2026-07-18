import Foundation
import Observation

enum ChargingSettingsOperationError: LocalizedError {
  case saveInProgress

  var errorDescription: String? {
    "Wait for the current charging settings change to finish before removing the background service."
  }
}

@MainActor
protocol ChargingSettingsManaging: AnyObject {
  /// All settings groups as a single unit, non-nil only once every group has
  /// loaded. Routing observation through one bundled value (instead of 7
  /// parallel optionals) means the model only has to track one property, and
  /// a new group added to `DaemonSettingsBundle` fails to compile here until
  /// its call sites catch up — turning a silent missed-sync into a build error.
  var settingsBundle: DaemonSettingsBundle? { get }
  var capabilities: DaemonCapabilities? { get }

  func setChargingManagementSettings(_ settings: ChargingManagementSettings) async throws -> ChargingManagementSettings
  func setChargingThresholdSettings(_ settings: ChargingThresholdSettings) async throws -> ChargingThresholdSettings
  func setAutomaticDischargeSettings(_ settings: AutomaticDischargeSettings) async throws -> AutomaticDischargeSettings
  func setSleepPreventionSettings(_ settings: SleepPreventionSettings) async throws -> SleepPreventionSettings
  func setHeatProtectionSettings(_ settings: HeatProtectionSettings) async throws -> HeatProtectionSettings
  func setMagSafeLEDSettings(_ settings: MagSafeLEDSettings) async throws -> MagSafeLEDSettings
  func setBatteryPercentageSettings(_ settings: BatteryPercentageSettings) async throws -> BatteryPercentageSettings
}

extension ChargingDaemonManager: ChargingSettingsManaging {}

struct ChargingSettingsAvailability: Equatable {
  let isResolved: Bool
  let management: Bool
  let sailingMode: Bool
  let automaticDischarge: Bool
  let sleepPrevention: Bool
  let heatProtection: Bool
  let magSafeLED: Bool

  var canAttemptManagement: Bool { !isResolved || management }

  init(capabilities: DaemonCapabilities?) {
    isResolved = capabilities != nil
    management = capabilities?.chargingControl ?? false
    sailingMode = capabilities?.sailingModeControl ?? false
    automaticDischarge = capabilities?.automaticDischargeControl ?? false
    sleepPrevention = capabilities?.sleepHooks ?? false
    heatProtection = capabilities?.heatProtectionControl ?? false
    magSafeLED = capabilities?.magSafeLEDControl ?? false
  }
}

@MainActor
@Observable
final class ChargingSettingsModel {
  private let client: any ChargingSettingsManaging
  private var isStopped = false

  let managementState: ManagementSettingsState
  let thresholdState: ThresholdSettingsState
  let automaticDischargeState: AutomaticDischargeSettingsState
  let sleepPreventionState: SleepPreventionSettingsState
  let heatProtectionState: HeatProtectionSettingsState
  let magSafeLEDState: MagSafeLEDSettingsState
  let batteryPercentageState: BatteryPercentageSettingsState

  private(set) var capabilities: DaemonCapabilities?
  private(set) var isLoaded: Bool

  var management: ChargingManagementSettings? { managementState.settings }
  var threshold: ChargingThresholdSettings? { thresholdState.settings }
  var automaticDischarge: AutomaticDischargeSettings? { automaticDischargeState.settings }
  var sleepPrevention: SleepPreventionSettings? { sleepPreventionState.settings }
  var heatProtection: HeatProtectionSettings? { heatProtectionState.settings }
  var magSafeLED: MagSafeLEDSettings? { magSafeLEDState.settings }
  var batteryPercentage: BatteryPercentageSettings? { batteryPercentageState.settings }

  /// True if ANY settings group is mid-save. This is a blunt, cross-group
  /// aggregate — named explicitly so it isn't mistaken for a single group's
  /// `isSaving` when gating scoped UI (that mistake caused unrelated saves to
  /// re-render the Manage Charging section). Use a specific group's own
  /// `XxxState.isSaving` for anything section-scoped.
  var isSavingAnyGroup: Bool {
    managementState.isSaving
      || thresholdState.isSaving
      || automaticDischargeState.isSaving
      || sleepPreventionState.isSaving
      || heatProtectionState.isSaving
      || magSafeLEDState.isSaving
      || batteryPercentageState.isSaving
  }

  /// The first error found across all groups, if any. A blunt, cross-group
  /// aggregate for tests/diagnostics that only need to know "did something
  /// fail" — use a specific group's own `XxxState.errorMessage` for anything
  /// section-scoped.
  var firstGroupErrorMessage: String? {
    managementState.errorMessage
      ?? thresholdState.errorMessage
      ?? automaticDischargeState.errorMessage
      ?? sleepPreventionState.errorMessage
      ?? heatProtectionState.errorMessage
      ?? magSafeLEDState.errorMessage
      ?? batteryPercentageState.errorMessage
  }

  var availability: ChargingSettingsAvailability { .init(capabilities: capabilities) }

  init(client: any ChargingSettingsManaging = ChargingDaemonManager.shared) {
    self.client = client
    let bundle = client.settingsBundle
    managementState = .init(
      initialSettings: bundle?.management,
      saveOperation: { try await client.setChargingManagementSettings($0) }
    )
    thresholdState = .init(
      initialSettings: bundle?.threshold,
      saveOperation: { try await client.setChargingThresholdSettings($0) }
    )
    automaticDischargeState = .init(
      initialSettings: bundle?.automaticDischarge,
      saveOperation: { try await client.setAutomaticDischargeSettings($0) }
    )
    sleepPreventionState = .init(
      initialSettings: bundle?.sleepPrevention,
      saveOperation: { try await client.setSleepPreventionSettings($0) }
    )
    heatProtectionState = .init(
      initialSettings: bundle?.heatProtection,
      saveOperation: { try await client.setHeatProtectionSettings($0) }
    )
    magSafeLEDState = .init(
      initialSettings: bundle?.magSafeLED,
      saveOperation: { try await client.setMagSafeLEDSettings($0) }
    )
    batteryPercentageState = .init(
      initialSettings: bundle?.batteryPercentage,
      saveOperation: { try await client.setBatteryPercentageSettings($0) }
    )
    capabilities = client.capabilities
    isLoaded = bundle != nil
    observeManagerStateChanges()
  }

  static func preview(managementEnabled: Bool) -> ChargingSettingsModel {
    ChargingSettingsModel(client: ChargingSettingsPreviewClient(managementEnabled: managementEnabled))
  }

  func setManagementEnabled(_ enabled: Bool) {
    managementState.setEnabled(enabled)
  }

  func setAutomaticDischargeEnabled(_ enabled: Bool) {
    automaticDischargeState.setEnabled(enabled)
  }

  func setSleepPreventionEnabled(_ enabled: Bool) {
    sleepPreventionState.setEnabled(enabled)
  }

  func setUseHardwarePercentage(_ enabled: Bool) {
    batteryPercentageState.setUseHardwarePercentage(enabled)
  }

  func disableManagementForDaemonUninstall() async throws {
    guard !isSavingAnyGroup else { throw ChargingSettingsOperationError.saveInProgress }
    guard management?.isEnabled == true else { return }
    try await managementState.setAndWait(.init(isEnabled: false))
  }

  func stop() {
    isStopped = true
    managementState.stop()
    thresholdState.stop()
    automaticDischargeState.stop()
    sleepPreventionState.stop()
    heatProtectionState.stop()
    magSafeLEDState.stop()
    batteryPercentageState.stop()
  }

  private func observeManagerStateChanges() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = client.settingsBundle
      _ = client.capabilities
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isStopped else { return }
        self.synchronizeFromManager()
        self.observeManagerStateChanges()
      }
    }
  }

  private func synchronizeFromManager() {
    if capabilities != client.capabilities {
      capabilities = client.capabilities
    }
    let bundle = client.settingsBundle
    managementState.synchronize(bundle?.management)
    thresholdState.synchronize(bundle?.threshold)
    automaticDischargeState.synchronize(bundle?.automaticDischarge)
    sleepPreventionState.synchronize(bundle?.sleepPrevention)
    heatProtectionState.synchronize(bundle?.heatProtection)
    magSafeLEDState.synchronize(bundle?.magSafeLED)
    batteryPercentageState.synchronize(bundle?.batteryPercentage)
    let managerIsLoaded = bundle != nil
    if isLoaded != managerIsLoaded {
      isLoaded = managerIsLoaded
    }
  }
}

@MainActor
@Observable
private final class ChargingSettingsPreviewClient: ChargingSettingsManaging {
  var chargingManagementSettings: ChargingManagementSettings?
  var chargingThresholdSettings: ChargingThresholdSettings? = .init()
  var automaticDischargeSettings: AutomaticDischargeSettings? = .init()
  var sleepPreventionSettings: SleepPreventionSettings? = .init()
  var heatProtectionSettings: HeatProtectionSettings? = .init()
  var magSafeLEDSettings: MagSafeLEDSettings? = .init()
  var batteryPercentageSettings: BatteryPercentageSettings? = .init()
  var capabilities: DaemonCapabilities?

  var settingsBundle: DaemonSettingsBundle? {
    guard
      let chargingManagementSettings, let chargingThresholdSettings,
      let automaticDischargeSettings, let sleepPreventionSettings,
      let heatProtectionSettings, let magSafeLEDSettings, let batteryPercentageSettings
    else { return nil }
    return DaemonSettingsBundle(
      management: chargingManagementSettings,
      threshold: chargingThresholdSettings,
      automaticDischarge: automaticDischargeSettings,
      sleepPrevention: sleepPreventionSettings,
      heatProtection: heatProtectionSettings,
      magSafeLED: magSafeLEDSettings,
      batteryPercentage: batteryPercentageSettings
    )
  }

  init(managementEnabled: Bool) {
    chargingManagementSettings = .init(isEnabled: managementEnabled)
  }

  func setChargingManagementSettings(_ value: ChargingManagementSettings) async throws -> ChargingManagementSettings { chargingManagementSettings = value; return value }
  func setChargingThresholdSettings(_ value: ChargingThresholdSettings) async throws -> ChargingThresholdSettings { chargingThresholdSettings = value; return value }
  func setAutomaticDischargeSettings(_ value: AutomaticDischargeSettings) async throws -> AutomaticDischargeSettings { automaticDischargeSettings = value; return value }
  func setSleepPreventionSettings(_ value: SleepPreventionSettings) async throws -> SleepPreventionSettings { sleepPreventionSettings = value; return value }
  func setHeatProtectionSettings(_ value: HeatProtectionSettings) async throws -> HeatProtectionSettings { heatProtectionSettings = value; return value }
  func setMagSafeLEDSettings(_ value: MagSafeLEDSettings) async throws -> MagSafeLEDSettings { magSafeLEDSettings = value; return value }
  func setBatteryPercentageSettings(_ value: BatteryPercentageSettings) async throws -> BatteryPercentageSettings { batteryPercentageSettings = value; return value }
}
