import Foundation
import Observation
import ServiceManagement
import os.log

enum ManageChargingFlowState: Equatable {
  case idle
  case installing
  case waitingForApproval(String)
  case verifying
  case repairing
  case uninstalling
  case uninstallFailed(String)
  case ready
  case failed(String)

  var isLoading: Bool {
    switch self {
    case .installing, .verifying, .repairing, .uninstalling:
      true
    case .idle, .waitingForApproval, .uninstallFailed, .ready, .failed:
      false
    }
  }

  var isDeterminingDaemonStatus: Bool {
    switch self {
    case .installing, .verifying, .repairing:
      true
    case .idle, .waitingForApproval, .uninstalling, .uninstallFailed, .ready, .failed:
      false
    }
  }

  var message: String? {
    switch self {
    case .idle, .ready:
      nil
    case .installing:
      "Setting up Charging daemon..."
    case .waitingForApproval(let message), .failed(let message):
      message
    case .verifying:
      "Connecting to Charging daemon..."
    case .repairing:
      "Repairing Charging daemon..."
    case .uninstalling:
      "Removing Charging daemon..."
    case .uninstallFailed:
      nil
    }
  }

  var uninstallErrorMessage: String? {
    guard case .uninstallFailed(let message) = self else { return nil }
    return message
  }

  var showsApprovalPrompt: Bool {
    if case .waitingForApproval = self {
      return true
    }
    return false
  }
}

@MainActor
@Observable
final class ChargingManagementController {
  private static let spinnerDelay: Duration = .milliseconds(150)
  private static let minimumSpinnerVisibleDuration: Duration = .milliseconds(300)

  private let daemonManager: ChargingDaemonManager
  private let logger = Logger.stasis("ChargingManagementController")

  private var enableTask: Task<Void, Never>?
  private var enableGeneration = 0
  private var buildCheckTask: Task<Void, Never>?
  private var uninstallTask: Task<Void, Never>?
  private var spinnerTask: Task<Void, Never>?
  private var spinnerShownAt: ContinuousClock.Instant?
  private var pendingLoadingState: ManageChargingFlowState?

  private(set) var flowState: ManageChargingFlowState = .idle
  private(set) var enableRequested = false

  var isLoading: Bool {
    flowState.isLoading || pendingLoadingState?.isLoading == true
  }

  var isDeterminingDaemonStatus: Bool {
    flowState.isDeterminingDaemonStatus
      || pendingLoadingState?.isDeterminingDaemonStatus == true
  }

  init(daemonManager: ChargingDaemonManager = .shared) {
    self.daemonManager = daemonManager
  }

  func requestEnable(
    hasAnyControl: Bool,
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) {
    guard hasAnyControl, uninstallTask == nil else { return }
    enableRequested = true
    buildCheckTask?.cancel()
    buildCheckTask = nil
    enableTask?.cancel()
    enableGeneration += 1
    let generation = enableGeneration
    enableTask = Task { [weak self] in
      await self?.enableChargingManagement(
        generation: generation,
        setManageCharging: setManageCharging
      )
    }
  }

  func cancelPendingWork() {
    enableTask?.cancel()
    enableTask = nil
    buildCheckTask?.cancel()
    buildCheckTask = nil
    cancelSpinner()
    if flowState.isLoading, uninstallTask == nil {
      flowState = .idle
    }
  }

  func disable(setManageCharging: @escaping @MainActor (Bool) -> Void) {
    cancelPendingWork()
    enableRequested = false
    flowState = .idle
    setManageCharging(false)
  }

  func requestUninstall(settingsModel: ChargingSettingsModel) {
    guard uninstallTask == nil else { return }
    cancelPendingWork()
    enableRequested = false
    flowState = .uninstalling
    uninstallTask = Task { [weak self, weak settingsModel] in
      guard let self, let settingsModel else { return }
      await self.uninstallDaemon(settingsModel: settingsModel)
    }
  }

  func checkApprovalStatus(
    hasAnyControl: Bool,
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) {
    daemonManager.refreshStatus()
    if daemonManager.daemonStatus == .installed, enableRequested {
      requestEnable(
        hasAnyControl: hasAnyControl,
        setManageCharging: setManageCharging
      )
    }
  }

  func reconcileOnAppear(
    hasAnyControl: Bool,
    manageCharging: Bool
  ) {
    guard manageCharging else { return }

    if daemonManager.daemonStatus == .installed,
       daemonManager.connectionStatus == .connecting {
      // Still connecting at startup; handleConnectionStatusChange will
      // resolve to .ready or .failed once the connection settles.
      return
    }

    if daemonManager.daemonStatus == .requiresApproval {
      flowState = .waitingForApproval(
        "Approve Stasis in System Settings to enable charge management."
      )
      return
    }

    guard
      hasAnyControl,
      daemonManager.daemonStatus == .installed,
      daemonManager.connectionStatus == .connected
    else {
      flowState = .failed("Charging daemon is unavailable; existing management state was preserved.")
      return
    }

    // The daemon looks healthy, but it may have been spawned from an older
    // app build. Verify its build identity in the background and repair the
    // registration when it differs from the bundled binary.
    guard uninstallTask == nil else { return }
    buildCheckTask?.cancel()
    buildCheckTask = Task { [weak self] in
      await self?.repairDaemonIfOutdated()
    }
  }

  private func repairDaemonIfOutdated() async {
    do {
      try await daemonManager.verifyConnection()
      try Task.checkCancellation()
      guard daemonManager.isDaemonOutdated else { return }

      scheduleSpinner(for: .repairing)
      _ = try await daemonManager.repairDaemonIfOutdated()
      try Task.checkCancellation()
      await finishSpinnerIfNeeded()
      guard !Task.isCancelled else { return }
      if daemonManager.daemonStatus == .installed,
         daemonManager.connectionStatus == .connected {
        flowState = .ready
      } else {
        handleUnavailableDaemonAfterRepair()
      }
    } catch is CancellationError {
      // A newer flow owns the shared spinner state now; leave it alone.
    } catch {
      logger.error("Charging daemon build check failed: \(error)")
      guard !Task.isCancelled else { return }
      await finishSpinnerIfNeeded()
      guard !Task.isCancelled else { return }
      flowState = .failed(error.localizedDescription)
    }
  }

  func handleDaemonStatusChange(
    _ newStatus: ChargingDaemonStatus
  ) {
    guard uninstallTask == nil else { return }

    // Approval can be revoked or granted outside the enable flow (e.g. a
    // reinstall with a changed daemon), so track it unconditionally.
    if newStatus == .requiresApproval {
      flowState = .waitingForApproval(
        "Approve Stasis in System Settings to enable charge management."
      )
      return
    }
    if flowState.showsApprovalPrompt {
      flowState = .idle
    }

    guard enableRequested else { return }

    switch newStatus {
    case .installed, .requiresApproval:
      // The enable flow drives its own state transitions once the
      // daemon is installed; don't clobber them here.
      break
    case .notInstalled:
      flowState = .failed("Charging daemon is not installed.")
    }
  }

  func handleConnectionStatusChange(
    _ newStatus: ChargingDaemonConnectionStatus,
    manageCharging: Bool
  ) {
    guard
      manageCharging,
      !flowState.isLoading,
      pendingLoadingState == nil
    else { return }

    switch newStatus {
    case .connecting:
      return
    case .connected:
      flowState = .ready
    case .disconnected, .interrupted, .invalidated, .startupFailed, .runtimeFailed:
      flowState = .failed(
        connectionStatusMessage(for: newStatus)
          ?? "Charging daemon disconnected."
      )
    }
  }

  func openApprovalSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func enableChargingManagement(
    generation: Int,
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) async {
    do {
      if daemonManager.daemonStatus != .installed {
        scheduleSpinner(for: .installing)
        try daemonManager.install()
      } else {
        daemonManager.refreshStatus()
      }

      try Task.checkCancellation()

      switch daemonManager.daemonStatus {
      case .installed:
        guard enableRequested else { return }
        scheduleSpinner(for: .verifying)
        try await verifyInstalledDaemon()
        try Task.checkCancellation()

        guard daemonManager.daemonStatus == .installed else {
          guard generation == enableGeneration else { return }
          await finishSpinnerIfNeeded()
          guard generation == enableGeneration else { return }
          handleUnavailableDaemonAfterRepair()
          return
        }
        guard daemonManager.connectionStatus == .connected else {
          throw XPCError.serviceUnavailable
        }

        guard generation == enableGeneration else { return }
        await finishSpinnerIfNeeded()
        guard generation == enableGeneration, enableRequested else { return }
        enableRequested = false
        flowState = .ready
        setManageCharging(true)
      case .requiresApproval:
        guard generation == enableGeneration else { return }
        await finishSpinnerIfNeeded()
        guard generation == enableGeneration, enableRequested else { return }
        flowState = .waitingForApproval(
          "Approve Stasis in System Settings to enable charge management."
        )
      case .notInstalled:
        guard generation == enableGeneration else { return }
        await finishSpinnerIfNeeded()
        guard generation == enableGeneration, enableRequested else { return }
        flowState = .failed("Charging daemon is not installed.")
      }
    } catch is CancellationError {
      // A newer requestEnable may have replaced this task; only the
      // current run may touch the shared spinner state.
      guard generation == enableGeneration else { return }
      await finishSpinnerIfNeeded()
    } catch {
      logger.error("Failed to enable charging management: \(error)")
      guard generation == enableGeneration else { return }
      await finishSpinnerIfNeeded()
      guard generation == enableGeneration, enableRequested else { return }
      flowState = .failed(error.localizedDescription)
    }
  }

  private func uninstallDaemon(settingsModel: ChargingSettingsModel) async {
    do {
      try await settingsModel.disableManagementForDaemonUninstall()
      try await daemonManager.uninstall()
      flowState = .idle
    } catch {
      logger.error("Failed to uninstall charging daemon: \(error)")
      flowState = .uninstallFailed(error.localizedDescription)
    }
    uninstallTask = nil
  }

  private func verifyInstalledDaemon() async throws {
    do {
      try await daemonManager.verifyConnection()
    } catch {
      guard shouldRepairAfterVerifyFailure else {
        throw error
      }

      logger.error("Charging daemon startup verify failed, attempting repair: \(error)")
      try await repairAndReverify()
      return
    }

    if daemonManager.isDaemonOutdated {
      scheduleSpinner(for: .repairing)
      _ = try await daemonManager.repairDaemonIfOutdated()
    }
  }

  private func repairAndReverify() async throws {
    scheduleSpinner(for: .repairing)
    try await daemonManager.repairInstallation()
    guard daemonManager.daemonStatus == .installed else { return }
    scheduleSpinner(for: .verifying)
    try await daemonManager.verifyConnection()
  }

  private var shouldRepairAfterVerifyFailure: Bool {
    switch daemonManager.connectionStatus {
    case .startupFailed, .invalidated, .disconnected:
      true
    case .connecting, .connected, .interrupted, .runtimeFailed:
      false
    }
  }

  private func handleUnavailableDaemonAfterRepair() {
    switch daemonManager.daemonStatus {
    case .installed:
      flowState = .idle
    case .requiresApproval:
      flowState = .waitingForApproval(
        "Approve Stasis in System Settings to enable charge management."
      )
    case .notInstalled:
      flowState = .failed("Charging daemon is not installed.")
    }
  }

  private func scheduleSpinner(for state: ManageChargingFlowState) {
    pendingLoadingState = state
    spinnerTask?.cancel()
    spinnerTask = Task { [weak self] in
      try? await Task.sleep(for: Self.spinnerDelay)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, self.pendingLoadingState == state else { return }
        self.spinnerShownAt = .now
        self.flowState = state
      }
    }
  }

  private func finishSpinnerIfNeeded() async {
    spinnerTask?.cancel()
    spinnerTask = nil
    pendingLoadingState = nil

    guard let spinnerShownAt else { return }
    let elapsed = spinnerShownAt.duration(to: .now)
    if elapsed < Self.minimumSpinnerVisibleDuration {
      try? await Task.sleep(for: Self.minimumSpinnerVisibleDuration - elapsed)
    }
    self.spinnerShownAt = nil
  }

  private func cancelSpinner() {
    spinnerTask?.cancel()
    spinnerTask = nil
    spinnerShownAt = nil
    pendingLoadingState = nil
  }

  private func connectionStatusMessage(for status: ChargingDaemonConnectionStatus) -> String? {
    switch status {
    case .disconnected:
      "Charging daemon is disconnected."
    case .connecting, .connected:
      nil
    case .interrupted:
      "Charging daemon connection was interrupted."
    case .invalidated:
      "Charging daemon connection was invalidated."
    case .startupFailed(let message), .runtimeFailed(let message):
      message
    }
  }
}
