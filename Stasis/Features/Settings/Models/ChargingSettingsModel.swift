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
  var chargingManagementSettings: ChargingManagementSettings? { get }
  var chargingThresholdSettings: ChargingThresholdSettings? { get }
  var automaticDischargeSettings: AutomaticDischargeSettings? { get }
  var sleepPreventionSettings: SleepPreventionSettings? { get }
  var heatProtectionSettings: HeatProtectionSettings? { get }
  var magSafeLEDSettings: MagSafeLEDSettings? { get }
  var batteryPercentageSettings: BatteryPercentageSettings? { get }
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
  private let sliderDebounce: Duration
  private var thresholdDebounceTask: Task<Void, Never>?
  private var heatDebounceTask: Task<Void, Never>?
  private var saveTasks: [String: Task<Void, Never>] = [:]
  private var isStopped = false

  private(set) var management: ChargingManagementSettings?
  private(set) var threshold: ChargingThresholdSettings?
  private(set) var automaticDischarge: AutomaticDischargeSettings?
  private(set) var sleepPrevention: SleepPreventionSettings?
  private(set) var heatProtection: HeatProtectionSettings?
  private(set) var magSafeLED: MagSafeLEDSettings?
  private(set) var batteryPercentage: BatteryPercentageSettings?
  private(set) var capabilities: DaemonCapabilities?
  private(set) var errorMessage: String?

  var isLoaded: Bool {
    management != nil && threshold != nil && automaticDischarge != nil
      && sleepPrevention != nil && heatProtection != nil && magSafeLED != nil
      && batteryPercentage != nil
  }

  var isSaving: Bool { !saveTasks.isEmpty }
  var availability: ChargingSettingsAvailability { .init(capabilities: capabilities) }

  init(
    client: any ChargingSettingsManaging = ChargingDaemonManager.shared,
    sliderDebounce: Duration = .milliseconds(250)
  ) {
    self.client = client
    self.sliderDebounce = sliderDebounce
    synchronizeFromManager()
    observeManagerStateChanges()
  }

  static func preview(managementEnabled: Bool) -> ChargingSettingsModel {
    ChargingSettingsModel(client: ChargingSettingsPreviewClient(managementEnabled: managementEnabled))
  }

  func setManagementEnabled(_ enabled: Bool) {
    guard let confirmed = management, confirmed.isEnabled != enabled else { return }
    enqueueGroupSave("management", optimistic: nil, rollback: { self.management = confirmed }) {
      self.management = try await self.client.setChargingManagementSettings(.init(isEnabled: enabled))
    }
  }

  func updateChargingThreshold(
    debounced: Bool = false,
    _ update: (inout ChargingThresholdSettings) -> Void
  ) {
    guard let confirmed = threshold else { return }
    var draft = confirmed
    update(&draft)
    guard draft != confirmed else { return }
    threshold = draft
    errorMessage = nil
    if debounced {
      thresholdDebounceTask?.cancel()
      thresholdDebounceTask = Task { [weak self, sliderDebounce] in
        try? await Task.sleep(for: sliderDebounce)
        guard !Task.isCancelled else { return }
        self?.saveChargingThreshold(draft, rollback: confirmed)
      }
    } else {
      thresholdDebounceTask?.cancel()
      saveChargingThreshold(draft, rollback: confirmed)
    }
  }

  func setAutomaticDischargeEnabled(_ enabled: Bool) {
    guard let confirmed = automaticDischarge, confirmed.isEnabled != enabled else { return }
    let draft = AutomaticDischargeSettings(isEnabled: enabled)
    enqueueGroupSave("discharge", optimistic: { self.automaticDischarge = draft }, rollback: { self.automaticDischarge = confirmed }) {
      self.automaticDischarge = try await self.client.setAutomaticDischargeSettings(draft)
    }
  }

  func setSleepPreventionEnabled(_ enabled: Bool) {
    guard let confirmed = sleepPrevention, confirmed.isEnabled != enabled else { return }
    let draft = SleepPreventionSettings(isEnabled: enabled)
    enqueueGroupSave("sleep", optimistic: { self.sleepPrevention = draft }, rollback: { self.sleepPrevention = confirmed }) {
      self.sleepPrevention = try await self.client.setSleepPreventionSettings(draft)
    }
  }

  func updateHeatProtection(
    debounced: Bool = false,
    _ update: (inout HeatProtectionSettings) -> Void
  ) {
    guard let confirmed = heatProtection else { return }
    var draft = confirmed
    update(&draft)
    guard draft != confirmed else { return }
    heatProtection = draft
    errorMessage = nil
    if debounced {
      heatDebounceTask?.cancel()
      heatDebounceTask = Task { [weak self, sliderDebounce] in
        try? await Task.sleep(for: sliderDebounce)
        guard !Task.isCancelled else { return }
        self?.saveHeatProtection(draft, rollback: confirmed)
      }
    } else {
      heatDebounceTask?.cancel()
      saveHeatProtection(draft, rollback: confirmed)
    }
  }

  func updateMagSafeLED(_ update: (inout MagSafeLEDSettings) -> Void) {
    guard let confirmed = magSafeLED else { return }
    var draft = confirmed
    update(&draft)
    guard draft != confirmed else { return }
    enqueueGroupSave("magsafe", optimistic: { self.magSafeLED = draft }, rollback: { self.magSafeLED = confirmed }) {
      self.magSafeLED = try await self.client.setMagSafeLEDSettings(draft)
    }
  }

  func setUseHardwarePercentage(_ enabled: Bool) {
    guard let confirmed = batteryPercentage, confirmed.useHardwarePercentage != enabled else { return }
    let draft = BatteryPercentageSettings(useHardwarePercentage: enabled)
    enqueueGroupSave("percentage", optimistic: { self.batteryPercentage = draft }, rollback: { self.batteryPercentage = confirmed }) {
      self.batteryPercentage = try await self.client.setBatteryPercentageSettings(draft)
    }
  }

  func clearError() { errorMessage = nil }

  func disableManagementForDaemonUninstall() async throws {
    guard saveTasks.isEmpty else { throw ChargingSettingsOperationError.saveInProgress }
    thresholdDebounceTask?.cancel()
    heatDebounceTask?.cancel()
    guard management?.isEnabled == true else { return }
    let confirmed = management
    do {
      management = try await client.setChargingManagementSettings(.init(isEnabled: false))
      errorMessage = nil
    } catch {
      management = confirmed
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func stop() {
    isStopped = true
    thresholdDebounceTask?.cancel()
    heatDebounceTask?.cancel()
    saveTasks.values.forEach { $0.cancel() }
    saveTasks.removeAll()
  }

  private func saveChargingThreshold(_ draft: ChargingThresholdSettings, rollback: ChargingThresholdSettings) {
    enqueueGroupSave("threshold", optimistic: nil, rollback: { self.threshold = rollback }) {
      self.threshold = try await self.client.setChargingThresholdSettings(draft)
    }
  }

  private func saveHeatProtection(_ draft: HeatProtectionSettings, rollback: HeatProtectionSettings) {
    enqueueGroupSave("heat", optimistic: nil, rollback: { self.heatProtection = rollback }) {
      self.heatProtection = try await self.client.setHeatProtectionSettings(draft)
    }
  }

  private func enqueueGroupSave(
    _ key: String,
    optimistic: (() -> Void)?,
    rollback: @escaping () -> Void,
    operation: @escaping () async throws -> Void
  ) {
    optimistic?()
    errorMessage = nil
    saveTasks[key]?.cancel()
    saveTasks[key] = Task { [weak self] in
      guard let self else { return }
      do {
        try await operation()
      } catch is CancellationError {
        return
      } catch {
        rollback()
        self.errorMessage = error.localizedDescription
      }
      self.saveTasks[key] = nil
    }
  }

  private func observeManagerStateChanges() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = client.chargingManagementSettings
      _ = client.chargingThresholdSettings
      _ = client.automaticDischargeSettings
      _ = client.sleepPreventionSettings
      _ = client.heatProtectionSettings
      _ = client.magSafeLEDSettings
      _ = client.batteryPercentageSettings
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
    if saveTasks["management"] == nil { management = client.chargingManagementSettings }
    if saveTasks["threshold"] == nil, thresholdDebounceTask == nil { threshold = client.chargingThresholdSettings }
    if saveTasks["discharge"] == nil { automaticDischarge = client.automaticDischargeSettings }
    if saveTasks["sleep"] == nil { sleepPrevention = client.sleepPreventionSettings }
    if saveTasks["heat"] == nil, heatDebounceTask == nil { heatProtection = client.heatProtectionSettings }
    if saveTasks["magsafe"] == nil { magSafeLED = client.magSafeLEDSettings }
    if saveTasks["percentage"] == nil { batteryPercentage = client.batteryPercentageSettings }
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
