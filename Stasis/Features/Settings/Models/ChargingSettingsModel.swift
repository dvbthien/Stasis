import Foundation
import Observation

enum ChargingSettingsOperationError: LocalizedError {
  case saveInProgress

  var errorDescription: String? {
    switch self {
    case .saveInProgress:
      "Wait for the current charging settings change to finish before removing the background service."
    }
  }
}

@MainActor
protocol ChargingSettingsManaging: AnyObject {
  var daemonSettingsState: DaemonSettingsState? { get }
  var daemonSnapshot: DaemonSnapshot? { get }

  func synchronizeChargingSettings(
    _ settings: DaemonSettings
  ) async throws -> DaemonSettingsState
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

  /// An unresolved capability set means the daemon has not returned its
  /// first snapshot yet. The UI must still allow starting/installing the
  /// daemon so it can perform capability probing.
  var canAttemptManagement: Bool {
    !isResolved || management
  }

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
  private struct PendingSave {
    let settings: DaemonSettings
    let appliesOptimistically: Bool
  }

  private let client: any ChargingSettingsManaging
  private let sliderDebounce: Duration
  private var confirmedSettings: DaemonSettings
  private var pendingSave: PendingSave?
  private var saveTask: Task<Void, Never>?
  private var debounceTask: Task<Void, Never>?
  private var isStopped = false

  private(set) var settings: DaemonSettings
  private(set) var capabilities: DaemonCapabilities?
  private(set) var isLoaded = false
  private(set) var isSaving = false
  private(set) var errorMessage: String?

  var availability: ChargingSettingsAvailability {
    ChargingSettingsAvailability(capabilities: capabilities)
  }

  init(
    client: any ChargingSettingsManaging = ChargingDaemonManager.shared,
    sliderDebounce: Duration = .milliseconds(250)
  ) {
    self.client = client
    self.sliderDebounce = sliderDebounce
    let initial = client.daemonSettingsState?.settings ?? DaemonSettings()
    settings = initial
    confirmedSettings = initial
    receiveDaemonState()
    observeDaemonState()
  }

  static func preview(managementEnabled: Bool) -> ChargingSettingsModel {
    var settings = DaemonSettings()
    settings.managementEnabled = managementEnabled
    return ChargingSettingsModel(
      client: ChargingSettingsPreviewClient(settings: settings)
    )
  }

  func set<Value: Equatable & Sendable>(
    _ keyPath: WritableKeyPath<DaemonSettings, Value>,
    to value: Value,
    debounced: Bool = false
  ) {
    guard settings[keyPath: keyPath] != value else { return }
    var updated = settings
    updated[keyPath: keyPath] = value
    settings = updated
    errorMessage = nil

    if debounced {
      scheduleDebouncedSave()
    } else {
      debounceTask?.cancel()
      debounceTask = nil
      enqueueSave(updated, appliesOptimistically: true)
    }
  }

  /// Management transitions are pessimistic: the toggle changes only after
  /// the daemon has persisted settings and reconciled/reset hardware.
  func setManagementEnabled(_ enabled: Bool) {
    guard settings.managementEnabled != enabled else { return }
    var updated = settings
    updated.managementEnabled = enabled
    errorMessage = nil
    debounceTask?.cancel()
    debounceTask = nil
    enqueueSave(updated, appliesOptimistically: false)
  }

  func clearError() {
    errorMessage = nil
  }

  /// Persists management as disabled before the daemon is removed so a later
  /// reinstall cannot unexpectedly resume the previous charging policy.
  func disableManagementForDaemonUninstall() async throws {
    guard saveTask == nil, !isSaving else {
      throw ChargingSettingsOperationError.saveInProgress
    }

    let hasPendingDebouncedSave = debounceTask != nil
    debounceTask?.cancel()
    debounceTask = nil
    pendingSave = nil

    guard settings.managementEnabled || hasPendingDebouncedSave else {
      errorMessage = nil
      return
    }

    var updated = settings
    updated.managementEnabled = false
    isSaving = true
    defer { isSaving = false }

    do {
      let state = try await client.synchronizeChargingSettings(updated)
      confirmedSettings = state.settings
      settings = state.settings
      isLoaded = true
      errorMessage = nil
    } catch {
      settings = confirmedSettings
      errorMessage = error.localizedDescription
      throw error
    }
  }

  func stop() {
    isStopped = true
    debounceTask?.cancel()
    debounceTask = nil
    saveTask?.cancel()
    saveTask = nil
    pendingSave = nil
  }

  private func scheduleDebouncedSave() {
    debounceTask?.cancel()
    debounceTask = Task { [weak self, sliderDebounce] in
      try? await Task.sleep(for: sliderDebounce)
      guard !Task.isCancelled, let self else { return }
      self.debounceTask = nil
      self.enqueueSave(self.settings, appliesOptimistically: true)
    }
  }

  private func enqueueSave(
    _ settings: DaemonSettings,
    appliesOptimistically: Bool
  ) {
    pendingSave = PendingSave(
      settings: settings,
      appliesOptimistically: appliesOptimistically
    )
    guard saveTask == nil else { return }
    saveTask = Task { [weak self] in
      await self?.runSaveLoop()
    }
  }

  private func runSaveLoop() async {
    isSaving = true
    while let request = pendingSave, !Task.isCancelled {
      pendingSave = nil
      do {
        let state = try await client.synchronizeChargingSettings(request.settings)
        confirmedSettings = state.settings
        isLoaded = true
        if pendingSave == nil, debounceTask == nil {
          settings = state.settings
        } else if !request.appliesOptimistically {
          // A later edit is already queued; keep that newer draft visible.
          settings = pendingSave?.settings ?? settings
        }
        errorMessage = nil
      } catch {
        pendingSave = nil
        debounceTask?.cancel()
        debounceTask = nil
        settings = confirmedSettings
        errorMessage = error.localizedDescription
        break
      }
    }
    isSaving = false
    saveTask = nil
  }

  private func observeDaemonState() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = client.daemonSettingsState
      _ = client.daemonSnapshot
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isStopped else { return }
        self.receiveDaemonState()
        self.observeDaemonState()
      }
    }
  }

  private func receiveDaemonState() {
    capabilities = client.daemonSnapshot?.capabilities
    guard let state = client.daemonSettingsState else { return }
    confirmedSettings = state.settings
    isLoaded = true
    if saveTask == nil, pendingSave == nil, debounceTask == nil {
      settings = state.settings
      errorMessage = nil
    }
  }
}

@MainActor
@Observable
private final class ChargingSettingsPreviewClient: ChargingSettingsManaging {
  var daemonSettingsState: DaemonSettingsState?
  var daemonSnapshot: DaemonSnapshot?

  init(settings: DaemonSettings) {
    daemonSettingsState = DaemonSettingsState(
      settings: settings,
      revision: 0,
      needsLegacyImport: false
    )
  }

  func synchronizeChargingSettings(
    _ settings: DaemonSettings
  ) async throws -> DaemonSettingsState {
    let state = DaemonSettingsState(
      settings: settings,
      revision: (daemonSettingsState?.revision ?? 0) + 1,
      needsLegacyImport: false
    )
    daemonSettingsState = state
    return state
  }
}
