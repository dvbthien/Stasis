import Foundation
import Observation
import os.log

/// Uses daemon snapshots as the authoritative source for the status icon and
/// menu. The app-side IOKit monitor remains available as an immediate fallback
/// while the daemon is unavailable or reconnecting.
@MainActor
@Observable
class BatteryService {
  var metrics = BatteryMetrics()
  var adapterMetrics = AdapterMetrics()
  private(set) var controlState = BatteryControlState()
  private(set) var deviceCapabilities = DeviceCapabilities.unknown

  private let ioKitService = IOKitService()
  private let daemonManager = ChargingDaemonManager.shared
  private let smcReader = SMCReaderHelperClient.shared

  private var ioKitMonitorTask: Task<Void, Never>?
  private var smcTelemetryTask: Task<Void, Never>?
  private var smcSingleTelemetryTask: Task<Void, Never>?

  private var fallbackMetrics = BatteryMetrics()
  private var fallbackAdapterMetrics = AdapterMetrics()
  private var telemetryRequested = false
  private var isStopped = false

  private let logger = Logger.stasis("BatteryService")

  init() {
    logger.info("BatteryService initialized")
    startIOKitMonitoring()
    daemonManager.startStateStreaming()
    handleDaemonStateChange()
    observeDaemonState()
  }

  func loadCapabilities() async {
    if let snapshot = authoritativeDaemonSnapshot {
      applyCapabilities(snapshot.capabilities)
      return
    }

    deviceCapabilities = .unknown
  }

  private var authoritativeDaemonSnapshot: DaemonSnapshot? {
    guard daemonManager.hasFreshDaemonSnapshot else { return nil }
    return daemonManager.daemonSnapshot
  }

  private func observeDaemonState() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = daemonManager.connectionStatus
      _ = daemonManager.daemonSnapshot
      _ = daemonManager.hasFreshDaemonSnapshot
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isStopped else { return }
        self.handleDaemonStateChange()
        self.observeDaemonState()
      }
    }
  }

  private func handleDaemonStateChange() {
    if let snapshot = authoritativeDaemonSnapshot {
      applyDaemonSnapshot(snapshot)
      stopIOKitMonitoring()
    } else {
      startIOKitMonitoring()
      applyFallbackSnapshot()
    }
    synchronizeTelemetryDemand()
  }

  private func startIOKitMonitoring() {
    guard !isStopped, ioKitMonitorTask == nil else { return }
    logger.info("Starting IOKit monitoring in main app")
    ioKitMonitorTask = Task { [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { return }
      for await (newBatteryMetrics, newAdapterMetrics) in self.ioKitService.metricsStream() {
        guard !Task.isCancelled else { break }
        self.handleIOKitUpdate(newBatteryMetrics, adapterUpdate: newAdapterMetrics)
      }
    }
  }

  private func stopIOKitMonitoring() {
    guard ioKitMonitorTask != nil else { return }
    logger.info("Stopping app-side IOKit fallback")
    ioKitMonitorTask?.cancel()
    ioKitMonitorTask = nil
    ioKitService.stopMonitoring()
  }

  func setFastTelemetryEnabled(_ enabled: Bool) {
    telemetryRequested = enabled
    synchronizeTelemetryDemand()
  }

  private func handleIOKitUpdate(_ newBatteryMetrics: BatteryMetrics, adapterUpdate: AdapterMetrics)
  {
    logger.debug("Received fallback IOKit update")
    fallbackMetrics = newBatteryMetrics
    fallbackAdapterMetrics = adapterUpdate

    if authoritativeDaemonSnapshot == nil {
      applyFallbackSnapshot()
    }
  }

  private func applyDaemonSnapshot(_ snapshot: DaemonSnapshot) {
    let updatedBattery = BatteryMetrics(
      batteryPercentage: snapshot.battery.displayedPercentage,
      hardwareBatteryPercentage: snapshot.battery.hardwarePercentage,
      isCharging: snapshot.battery.isCharging,
      timeRemaining: snapshot.battery.timeRemaining,
      batteryVoltage: snapshot.battery.voltage,
      batteryCurrent: snapshot.battery.current,
      batteryPower: snapshot.battery.power,
      batteryTemperature: snapshot.battery.temperature,
      batteryHealth: snapshot.battery.health,
      cycleCount: snapshot.battery.cycleCount,
      externalConnected: snapshot.adapter.physicallyConnected
    )
    let updatedAdapter = AdapterMetrics(
      adapterConnected: snapshot.adapter.physicallyConnected,
      powerEnabled: snapshot.adapter.powerEnabled,
      adapterVoltage: snapshot.adapter.voltage,
      adapterCurrent: snapshot.adapter.current,
      adapterPower: snapshot.adapter.power
    )

    applyMetrics(updatedBattery, adapter: updatedAdapter)
    applyCapabilities(snapshot.capabilities)
    scheduleSMCTelemetryRefresh()
  }

  private func applyFallbackSnapshot() {
    applyMetrics(fallbackMetrics, adapter: fallbackAdapterMetrics)
    scheduleSMCTelemetryRefresh()
  }

  private func applyMetrics(_ updatedBattery: BatteryMetrics, adapter updatedAdapter: AdapterMetrics) {
    if updatedBattery != metrics {
      metrics = updatedBattery
    }
    if updatedAdapter != adapterMetrics {
      adapterMetrics = updatedAdapter
    }
    updateControlState(from: updatedBattery, adapter: updatedAdapter)
  }

  private func applyCapabilities(_ capabilities: DaemonCapabilities) {
    deviceCapabilities = DeviceCapabilities(
      chargingControl: capabilities.chargingControl,
      adapterControl: capabilities.adapterControl,
      hasMagSafe: capabilities.magSafeLEDKeyAvailable,
      magsafeLEDControl: capabilities.magSafeLEDControl
    )
  }

  private func synchronizeTelemetryDemand() {
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
        await self.refreshSMCTelemetryOnce()
        try? await Task.sleep(for: .seconds(1))
      }
      self.smcTelemetryTask = nil
      if self.telemetryRequested, !self.isStopped {
        self.synchronizeTelemetryDemand()
      }
    }
  }

  private func stopSMCTelemetryPolling() {
    smcTelemetryTask?.cancel()
    smcTelemetryTask = nil
  }

  private func scheduleSMCTelemetryRefresh() {
    guard !isStopped, !telemetryRequested else { return }
    smcSingleTelemetryTask?.cancel()
    smcSingleTelemetryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard
        !Task.isCancelled,
        let self,
        !self.isStopped,
        !self.telemetryRequested
      else {
        return
      }

      await self.refreshSMCTelemetryOnce()
      self.smcSingleTelemetryTask = nil
    }
  }

  private func refreshSMCTelemetryOnce() async {
    do {
      applySMCTelemetryOverlay(try await smcReader.readAllMetrics())
    } catch {
      logger.error("Could not read SMC telemetry: \(error.localizedDescription)")
    }
  }

  private func applySMCTelemetryOverlay(_ telemetry: SMCTelemetryMetrics) {
    var updatedBattery = metrics
    var updatedAdapter = adapterMetrics

    updatedBattery.batteryVoltage = telemetry.batteryVoltage
    updatedBattery.batteryCurrent = telemetry.batteryCurrent
    updatedBattery.batteryPower = telemetry.batteryPower

    updatedAdapter.adapterVoltage = telemetry.adapterVoltage
    updatedAdapter.adapterCurrent = telemetry.adapterCurrent
    updatedAdapter.adapterPower = telemetry.adapterPower

    applyMetrics(updatedBattery, adapter: updatedAdapter)
  }

  private func updateControlState(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
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
    smcSingleTelemetryTask?.cancel()
    smcSingleTelemetryTask = nil
    stopSMCTelemetryPolling()
    smcReader.invalidate()
    stopIOKitMonitoring()
  }
}
