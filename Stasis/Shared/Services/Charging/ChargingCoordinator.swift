import Foundation
import Observation
import os.log
import smc_power

/// Phase-5 compatibility coordinator. The daemon owns all hardware writes;
/// this object keeps the old policy running only as a shadow for comparison.
@MainActor
@Observable
final class ChargingCoordinator {
  private let batteryService: BatteryService
  private let daemonManager = ChargingDaemonManager.shared

  private var metricsObservation: Task<Void, Never>?

  private var lastAdapterConnected: Bool?
  private var lastManagementEnabled: Bool?
  private var hasReachedChargeLimit = false
  private var isStopped = false

  private(set) var chargeLimitOverrideActive = false
  private(set) var forceDischargeActive = false

  private let logger = Logger.stasis("ChargingCoordinatorShadow")

  init(batteryService: BatteryService) {
    self.batteryService = batteryService
    startObservingMetrics()
    observeDaemonSnapshot()
  }

  private func startObservingMetrics() {
    metricsObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        self.evaluateShadow(controlState: self.batteryService.controlState)
        await withCheckedContinuation { continuation in
          withObservationTracking {
            _ = self.batteryService.controlState
          } onChange: {
            Task { @MainActor in continuation.resume() }
          }
        }
      }
    }
  }

  private func observeDaemonSnapshot() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = daemonManager.daemonSnapshot
      _ = daemonManager.daemonSettingsState
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isStopped else { return }
        self.applyDaemonPolicyState()
        self.observeDaemonSnapshot()
      }
    }
    applyDaemonPolicyState()
  }

  private func applyDaemonPolicyState() {
    guard let policy = daemonManager.daemonSnapshot?.policy else { return }
    chargeLimitOverrideActive = policy.chargeLimitOverrideActive
    forceDischargeActive = policy.forceDischargeActive
    evaluateShadow(controlState: batteryService.controlState)
  }

  private func evaluateShadow(controlState: BatteryControlState) {
    guard let settings = daemonManager.daemonSettingsState?.settings else { return }
    let adapterChanged = lastAdapterConnected != controlState.adapterConnected
    let managementChanged = lastManagementEnabled != settings.managementEnabled
    lastAdapterConnected = controlState.adapterConnected
    lastManagementEnabled = settings.managementEnabled

    guard settings.managementEnabled, controlState.adapterConnected else {
      hasReachedChargeLimit = false
      return
    }

    let policySettings = ChargingSettingsSnapshot(
      settings: settings,
      chargeLimitOverrideActive: chargeLimitOverrideActive
    )
    var decision = ChargeLimitPolicy.evaluate(
      controlState: controlState,
      settings: policySettings,
      stateWasCleared: adapterChanged || managementChanged,
      hasReachedChargeLimit: &hasReachedChargeLimit
    )
    HeatProtectionPolicy.apply(
      to: &decision,
      controlState: controlState,
      settings: policySettings
    )
    ForceDischargePolicy.apply(to: &decision, isActive: forceDischargeActive)

    logger.debug(
      "Shadow decision charging=\(String(describing: decision.desiredCharging), privacy: .public) adapter=\(String(describing: decision.desiredAdapter), privacy: .public) reason=\(decision.reason ?? "none", privacy: .public)"
    )
    compareWithDaemon(decision)
  }

  private func compareWithDaemon(_ shadow: ChargingDecision) {
    guard
      let snapshot = daemonManager.daemonSnapshot,
      snapshot.capabilities.chargeControlMode == .legacy
    else { return }

    let daemon = snapshot.policy
    if daemon.desiredCharging != shadow.desiredCharging
      || daemon.desiredAdapter != shadow.desiredAdapter
      || daemon.desiredLEDStateRawValue != shadow.desiredLED?.rawValue
    {
      logger.warning(
        "Daemon/shadow decision mismatch at revision \(snapshot.runtime.settingsRevision)"
      )
    }
  }

  func toggleChargeLimitOverride() {
    let target = !chargeLimitOverrideActive
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.daemonManager.setChargeLimitOverride(target)
      } catch {
        self.logger.error("Charge-limit override failed: \(error.localizedDescription)")
      }
    }
  }

  func toggleForceDischarge() {
    let target = !forceDischargeActive
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.daemonManager.setForceDischarge(target)
      } catch {
        self.logger.error("Force discharge failed: \(error.localizedDescription)")
      }
    }
  }

  func stop() {
    isStopped = true
    metricsObservation?.cancel()
    metricsObservation = nil
  }
}
