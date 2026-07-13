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
  case ready
  case failed(String)

  var isLoading: Bool {
    switch self {
    case .installing, .verifying, .repairing:
      true
    case .idle, .waitingForApproval, .ready, .failed:
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
    }
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

  private let helperManager: ChargingDaemonManager
  private let logger = Logger.stasis("ChargingManagementController")

  private var enableTask: Task<Void, Never>?
  private var spinnerTask: Task<Void, Never>?
  private var spinnerShownAt: ContinuousClock.Instant?
  private var pendingLoadingState: ManageChargingFlowState?

  private(set) var flowState: ManageChargingFlowState = .idle
  private(set) var enableRequested = false

  init(helperManager: ChargingDaemonManager = .shared) {
    self.helperManager = helperManager
  }

  func requestEnable(
    hasAnyControl: Bool,
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) {
    guard hasAnyControl else { return }
    enableRequested = true
    enableTask?.cancel()
    enableTask = Task { [weak self] in
      await self?.enableChargingManagement(setManageCharging: setManageCharging)
    }
  }

  func cancelPendingWork() {
    enableTask?.cancel()
    enableTask = nil
    cancelSpinner()
    if flowState.isLoading {
      flowState = .idle
    }
  }

  func disable(setManageCharging: @escaping @MainActor (Bool) -> Void) {
    cancelPendingWork()
    enableRequested = false
    setManageCharging(false)
  }

  func checkApprovalStatus(
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) {
    helperManager.refreshStatus()
    if helperManager.helperStatus == .installed, enableRequested {
      requestEnable(
        hasAnyControl: true,
        setManageCharging: setManageCharging
      )
    }
  }

  func reconcileOnAppear(
    hasAnyControl: Bool,
    manageCharging: Bool
  ) {
    guard manageCharging else { return }
    guard
      hasAnyControl,
      helperManager.helperStatus == .installed,
      helperManager.connectionStatus == .connected
    else {
      flowState = .failed("Charging daemon is unavailable; existing management state was preserved.")
      return
    }
  }

  func handleHelperStatusChange(
    _ newStatus: ChargingHelperStatus
  ) {
    guard newStatus != .installed else { return }

    if enableRequested {
      switch newStatus {
      case .notInstalled:
        flowState = .failed("Charging daemon is not installed.")
      case .requiresApproval:
        flowState = .waitingForApproval(
          "Approve Stasis in System Settings to enable charge management."
        )
      case .installed:
        flowState = .idle
      }
    }
  }

  func handleConnectionStatusChange(
    _ newStatus: ChargingDaemonConnectionStatus,
    manageCharging: Bool
  ) {
    guard manageCharging else { return }
    if newStatus == .connected {
      flowState = .ready
      return
    }
    flowState = .failed(connectionStatusMessage(for: newStatus) ?? "Charging daemon disconnected.")
  }

  func openApprovalSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func enableChargingManagement(
    setManageCharging: @escaping @MainActor (Bool) -> Void
  ) async {
    do {
      if helperManager.helperStatus != .installed {
        scheduleSpinner(for: .installing)
        try helperManager.install()
      } else {
        helperManager.refreshStatus()
      }

      try Task.checkCancellation()

      switch helperManager.helperStatus {
      case .installed:
        guard enableRequested else { return }
        scheduleSpinner(for: .verifying)
        try await verifyInstalledHelper()
        try Task.checkCancellation()

        guard helperManager.helperStatus == .installed else {
          handleUnavailableHelperAfterRepair()
          await finishSpinnerIfNeeded()
          return
        }
        guard helperManager.connectionStatus == .connected else {
          throw XPCError.helperUnavailable
        }

        await finishSpinnerIfNeeded()
        guard enableRequested else { return }
        enableRequested = false
        flowState = .ready
        setManageCharging(true)
      case .requiresApproval:
        await finishSpinnerIfNeeded()
        guard enableRequested else { return }
        flowState = .waitingForApproval(
          "Approve Stasis in System Settings to enable charge management."
        )
      case .notInstalled:
        await finishSpinnerIfNeeded()
        guard enableRequested else { return }
        flowState = .failed("Charging daemon is not installed.")
      }
    } catch is CancellationError {
      await finishSpinnerIfNeeded()
    } catch {
      await finishSpinnerIfNeeded()
      logger.error("Failed to enable charging management: \(error)")
      guard enableRequested else { return }
      flowState = .failed(error.localizedDescription)
    }
  }

  private func verifyInstalledHelper() async throws {
    do {
      try await helperManager.verifyConnection()
    } catch {
      guard shouldRepairAfterVerifyFailure else {
        throw error
      }

      logger.error("Charging daemon startup verify failed, attempting repair: \(error)")
      scheduleSpinner(for: .repairing)
      try await helperManager.repairInstallation()
      guard helperManager.helperStatus == .installed else { return }
      scheduleSpinner(for: .verifying)
      try await helperManager.verifyConnection()
    }
  }

  private var shouldRepairAfterVerifyFailure: Bool {
    switch helperManager.connectionStatus {
    case .startupFailed, .invalidated, .disconnected:
      true
    case .connecting, .connected, .interrupted, .runtimeFailed:
      false
    }
  }

  private func handleUnavailableHelperAfterRepair() {
    switch helperManager.helperStatus {
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
