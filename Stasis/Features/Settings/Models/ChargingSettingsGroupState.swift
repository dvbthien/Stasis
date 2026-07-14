import Foundation
import Observation

@MainActor
@Observable
final class ChargingSettingsGroupState<Settings: Equatable> {
  private let saveOperation: (Settings) async throws -> Settings

  @ObservationIgnored private var confirmedSettings: Settings?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var pendingSettings: Settings?
  @ObservationIgnored private var generation = 0

  private(set) var settings: Settings?
  private(set) var isSaving = false
  private(set) var errorMessage: String?

  init(
    initialSettings: Settings?,
    saveOperation: @escaping (Settings) async throws -> Settings
  ) {
    settings = initialSettings
    confirmedSettings = initialSettings
    self.saveOperation = saveOperation
  }

  @inline(never)
  deinit {
    saveTask?.cancel()
  }

  func set(_ draft: Settings) {
    guard draft != settings else { return }

    settings = draft
    errorMessage = nil

    guard saveTask == nil else {
      pendingSettings = draft
      return
    }

    startSaving(draft)
  }

  func setAndWait(_ draft: Settings) async throws {
    guard draft != settings else { return }

    if let saveTask {
      await saveTask.value
      try Task.checkCancellation()
      try await setAndWait(draft)
      return
    }

    let rollback = confirmedSettings ?? settings
    generation += 1
    let currentGeneration = generation
    settings = draft
    isSaving = true
    errorMessage = nil
    do {
      let confirmed = try await saveOperation(draft)
      guard currentGeneration == generation else { return }
      confirmedSettings = confirmed
      settings = confirmed
      isSaving = false
    } catch {
      guard currentGeneration == generation else { throw error }
      settings = rollback
      errorMessage = error.localizedDescription
      isSaving = false
      throw error
    }
  }

  func synchronize(_ daemonSettings: Settings?) {
    guard !isSaving, daemonSettings != settings else { return }
    confirmedSettings = daemonSettings
    settings = daemonSettings
  }

  func clearError() {
    errorMessage = nil
  }

  func stop() {
    generation += 1
    saveTask?.cancel()
    saveTask = nil
    pendingSettings = nil
    isSaving = false
  }

  private func startSaving(_ draft: Settings) {
    generation += 1
    let currentGeneration = generation
    isSaving = true
    errorMessage = nil
    let rollback = confirmedSettings

    saveTask = Task { [weak self] in
      guard let self else { return }
      do {
        let confirmed = try await saveOperation(draft)
        finishSaving(confirmed, generation: currentGeneration)
      } catch is CancellationError {
        finishCancellation(generation: currentGeneration)
      } catch {
        finishSaving(
          rollback: rollback,
          error: error,
          generation: currentGeneration
        )
      }
    }
  }

  private func finishSaving(_ confirmed: Settings, generation currentGeneration: Int) {
    guard currentGeneration == generation else { return }
    confirmedSettings = confirmed
    saveTask = nil
    savePendingSettingsOrFinish()
  }

  private func finishSaving(
    rollback: Settings?,
    error: Error,
    generation currentGeneration: Int
  ) {
    guard currentGeneration == generation else { return }
    saveTask = nil

    if pendingSettings != nil {
      savePendingSettingsOrFinish()
    } else {
      settings = rollback
      errorMessage = error.localizedDescription
      isSaving = false
    }
  }

  private func finishCancellation(generation currentGeneration: Int) {
    guard currentGeneration == generation else { return }
    saveTask = nil
    pendingSettings = nil
    settings = confirmedSettings
    isSaving = false
  }

  private func savePendingSettingsOrFinish() {
    if let pendingSettings {
      self.pendingSettings = nil

      if pendingSettings != confirmedSettings {
        startSaving(pendingSettings)
        return
      }
    }

    settings = confirmedSettings
    isSaving = false
  }
}
