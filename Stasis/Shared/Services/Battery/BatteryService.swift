import Foundation
import Observation
import os.log

/// Uses daemon snapshots as the authoritative source for policy-affected state
/// (percentages, charging, adapter). Hardware readings the daemon does not own
/// (capacities, health, temperature, cycle count) always come from the
/// app-side IOKit monitor, which also acts as a full fallback while the daemon
/// is unavailable or reconnecting.
@MainActor
@Observable
class BatteryService {
  var metrics = BatteryMetrics()
  var adapterMetrics = AdapterMetrics()
  private(set) var controlState = BatteryControlState()
  private(set) var deviceCapabilities = DeviceCapabilities.unknown

  /// True once `deviceCapabilities` reflects a real daemon snapshot. An
  /// all-false value can be legitimate on unsupported hardware, so waiting
  /// UIs must gate on this flag instead of comparing against `.unknown`.
  private(set) var capabilitiesLoaded = false

  private let ioKitService = IOKitService()
  private let daemonManager = ChargingDaemonManager.shared
  private let smcReader = StasisHelperClient.shared

  private var ioKitMonitorTask: Task<Void, Never>?
  private var smcTelemetryTask: Task<Void, Never>?

  private var ioKitMetrics = BatteryMetrics()
  private var ioKitAdapterMetrics = AdapterMetrics()
  private var smcTelemetry: SMCTelemetryMetrics?
  private var telemetryRequested = false
  private var isStopped = false

  private let logger = Logger.stasis("BatteryService")

  init() {
    logger.info("BatteryService initialized")
    startIOKitMonitoring()
    daemonManager.startStateStreaming()
    refreshMetrics()
    observeDaemonSnapshotAuthority()
  }

  private var authoritativeDaemonSnapshot: DaemonSnapshot? {
    guard daemonManager.hasFreshDaemonSnapshot else { return nil }
    return daemonManager.daemonSnapshot
  }

  private func observeDaemonSnapshotAuthority() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = daemonManager.connectionStatus
      _ = daemonManager.daemonSnapshot
      _ = daemonManager.hasFreshDaemonSnapshot
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isStopped else { return }
        self.refreshMetrics()
        self.observeDaemonSnapshotAuthority()
      }
    }
  }

  private func startIOKitMonitoring() {
    guard !isStopped, ioKitMonitorTask == nil else { return }
    logger.info("Starting app-side IOKit monitoring")
    ioKitMonitorTask = Task { [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { return }
      for await (newBatteryMetrics, newAdapterMetrics) in self.ioKitService.metricsStream() {
        guard !Task.isCancelled else { break }
        self.receiveIOKitMetrics(newBatteryMetrics, adapter: newAdapterMetrics)
      }
    }
  }

  private func stopIOKitMonitoring() {
    guard ioKitMonitorTask != nil else { return }
    logger.info("Stopping app-side IOKit monitoring")
    ioKitMonitorTask?.cancel()
    ioKitMonitorTask = nil
    ioKitService.stopMonitoring()
  }

  func setFastTelemetryEnabled(_ enabled: Bool) {
    telemetryRequested = enabled
    updateTelemetryPollingState()
  }

  private func receiveIOKitMetrics(
    _ newBatteryMetrics: BatteryMetrics,
    adapter newAdapterMetrics: AdapterMetrics
  ) {
    logger.debug("Received IOKit update")
    ioKitMetrics = newBatteryMetrics
    ioKitAdapterMetrics = newAdapterMetrics
    refreshMetrics()
  }

  /// Rebuilds the published metrics from the three sources: IOKit readings
  /// are the base, SMC telemetry supplies the electrical values, and a fresh
  /// daemon snapshot overrides only the fields the daemon actually owns.
  private func refreshMetrics() {
    var updatedBattery = ioKitMetrics
    var updatedAdapter = ioKitAdapterMetrics

    if let telemetry = smcTelemetry {
      updatedBattery.batteryVoltage = telemetry.batteryVoltage
      updatedBattery.batteryCurrent = telemetry.batteryCurrent
      updatedBattery.batteryPower = telemetry.batteryPower

      updatedAdapter.adapterVoltage = telemetry.adapterVoltage
      updatedAdapter.adapterCurrent = telemetry.adapterCurrent
      updatedAdapter.adapterPower = telemetry.adapterPower
    }

    if let snapshot = authoritativeDaemonSnapshot {
      updatedBattery.batteryPercentage = snapshot.battery.displayedPercentage
      updatedBattery.hardwareBatteryPercentage = snapshot.battery.hardwarePercentage
      updatedBattery.isCharging = snapshot.battery.isCharging
      updatedBattery.timeRemaining = snapshot.battery.timeRemaining
      // "Running on AC power" (false during force discharge), as opposed to
      // physicallyConnected ("cable attached"). Nil from daemons that predate
      // the field — keep the app-side IOKit value then.
      if let externalConnected = snapshot.battery.externalConnected {
        updatedBattery.externalConnected = externalConnected
      }

      updatedAdapter.adapterConnected = snapshot.adapter.physicallyConnected
      updatedAdapter.powerEnabled = snapshot.adapter.powerEnabled

      updateDeviceCapabilities(from: snapshot.capabilities)
    }

    commitMetrics(updatedBattery, adapter: updatedAdapter)
  }

  private func commitMetrics(_ updatedBattery: BatteryMetrics, adapter updatedAdapter: AdapterMetrics) {
    if updatedBattery != metrics {
      metrics = updatedBattery
    }
    if updatedAdapter != adapterMetrics {
      adapterMetrics = updatedAdapter
    }
    updateBatteryObservationState(from: updatedBattery, adapter: updatedAdapter)
  }

  private func updateDeviceCapabilities(from capabilities: DaemonCapabilities) {
    capabilitiesLoaded = true
    deviceCapabilities = DeviceCapabilities(
      chargingControl: capabilities.chargingControl,
      adapterControl: capabilities.adapterControl,
      hasMagSafe: capabilities.magSafeLEDKeyAvailable,
      magsafeLEDControl: capabilities.magSafeLEDControl
    )
  }

  private func updateTelemetryPollingState() {
    guard !isStopped else { return }
    if telemetryRequested {
      startSMCTelemetryPolling()
    } else {
      stopSMCTelemetryPolling()
    }
  }

  private func startSMCTelemetryPolling() {
    guard smcTelemetryTask == nil else {
      return
    }

    smcTelemetryTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled, self.telemetryRequested, !self.isStopped {
        await self.refreshSMCTelemetry()
        try? await Task.sleep(for: .seconds(1))
      }
      self.smcTelemetryTask = nil
      if self.telemetryRequested, !self.isStopped {
        self.updateTelemetryPollingState()
      }
    }
  }

  private func stopSMCTelemetryPolling() {
    smcTelemetryTask?.cancel()
    smcTelemetryTask = nil
  }

  private func refreshSMCTelemetry() async {
    do {
      smcTelemetry = try await smcReader.readAllMetrics()
      refreshMetrics()
    } catch {
      logger.error("Could not read SMC telemetry: \(error.localizedDescription)")
    }
  }

  private func updateBatteryObservationState(
    from metrics: BatteryMetrics,
    adapter: AdapterMetrics
  ) {
    let newState = BatteryControlState(
      batteryPercentage: metrics.batteryPercentage,
      hardwareBatteryPercentage: metrics.hardwareBatteryPercentage,
      adapterConnected: adapter.adapterConnected,
      batteryTemperature: metrics.batteryTemperature
    )
    if newState != controlState {
      controlState = newState
    }
  }

  func stop() {
    logger.info("BatteryService stopping")
    isStopped = true
    telemetryRequested = false
    stopSMCTelemetryPolling()
    smcReader.invalidate()
    stopIOKitMonitoring()
  }
}
