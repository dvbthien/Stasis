import Foundation
import Observation
import os.log
import smc_power

/// Uses daemon snapshots as the authoritative source for the status icon and
/// menu. The app-side IOKit monitor and read-only SMC helper remain available
/// as an immediate fallback while the daemon is unavailable or reconnecting.
@MainActor
@Observable
class BatteryService {
  var metrics = BatteryMetrics()
  var adapterMetrics = AdapterMetrics()
  private(set) var controlState = BatteryControlState()
  private(set) var deviceCapabilities = DeviceCapabilities.unknown

  private let ioKitService = IOKitService()
  private let daemonManager = ChargingDaemonManager.shared
  private var smcPoller: SMCMetricsPoller!

  private var ioKitMonitorTask: Task<Void, Never>?
  private var daemonTelemetrySyncTask: Task<Void, Never>?

  private var fallbackMetrics = BatteryMetrics()
  private var fallbackAdapterMetrics = AdapterMetrics()
  private var fallbackFastPollingActive = false
  private var telemetryRequested = false
  private var appliedDaemonTelemetry = false
  private var desiredDaemonTelemetry = false
  private var isStopped = false

  private let logger = Logger.stasis("BatteryService")

  init() {
    logger.info("BatteryService initialized")
    smcPoller = SMCMetricsPoller(
      serviceName: "com.srimanachanta.stasis-monitor-helper",
      onReading: { [weak self] battery, adapter in
        self?.handleSMCReading(battery, adapter)
      }
    )
    startIOKitMonitoring()
    daemonManager.startStateStreaming()
    handleDaemonStateChange()
    observeDaemonState()
    scheduleSinglePoll()
  }

  func loadCapabilities() async {
    if let snapshot = authoritativeDaemonSnapshot {
      applyCapabilities(snapshot.capabilities)
      return
    }

    guard let capabilities = await smcPoller.loadCapabilities() else {
      return
    }
    self.deviceCapabilities = capabilities
    logger.info(
      "Capabilities loaded: charging=\(capabilities.chargingControl), adapter=\(capabilities.adapterControl), magSafe=\(capabilities.hasMagSafe)"
    )
  }

  private var authoritativeDaemonSnapshot: DaemonSnapshot? {
    guard daemonManager.connectionStatus == .connected else { return nil }
    return daemonManager.daemonSnapshot
  }

  private func observeDaemonState() {
    guard !isStopped else { return }
    withObservationTracking {
      _ = daemonManager.connectionStatus
      _ = daemonManager.daemonSnapshot
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
    } else {
      applyFallbackSnapshot()
      if appliedDaemonTelemetry {
        // XPC invalidation/interruption removes this client's demand in the
        // daemon, so no disable command is needed on a broken connection.
        appliedDaemonTelemetry = false
      }
    }
    synchronizeTelemetrySources()
  }

  private func startIOKitMonitoring() {
    logger.info("Starting IOKit monitoring in main app")
    ioKitMonitorTask = Task {
      for await (newBatteryMetrics, newAdapterMetrics) in self.ioKitService.metricsStream() {
        guard !Task.isCancelled else { break }
        self.handleIOKitUpdate(newBatteryMetrics, adapterUpdate: newAdapterMetrics)
      }
    }
  }

  func enableFastPolling() {
    telemetryRequested = true
    synchronizeTelemetrySources()
  }

  func disableFastPolling() {
    telemetryRequested = false
    synchronizeTelemetrySources()
  }

  func scheduleSinglePoll(delay: Duration = .seconds(3)) {
    guard authoritativeDaemonSnapshot == nil else { return }
    smcPoller.scheduleSinglePoll(delay: delay)
    logger.debug("Scheduled fallback SMC update")
  }

  private func handleSMCReading(
    _ batteryReading: SMCBatteryReading, _ adapterReading: SMCAdapterReading
  ) {
    fallbackMetrics.batteryVoltage = batteryReading.batteryVoltage
    fallbackMetrics.batteryCurrent = batteryReading.batteryCurrent
    fallbackMetrics.batteryPower = batteryReading.batteryPower

    fallbackAdapterMetrics.adapterVoltage = adapterReading.adapterVoltage
    fallbackAdapterMetrics.adapterCurrent = adapterReading.adapterCurrent
    fallbackAdapterMetrics.adapterPower = adapterReading.adapterPower

    if fallbackAdapterMetrics.adapterConnected {
      fallbackMetrics.isCharging = batteryReading.batteryPower > 0
    }

    if authoritativeDaemonSnapshot == nil {
      applyFallbackSnapshot()
    }
  }

  private func handleIOKitUpdate(_ newBatteryMetrics: BatteryMetrics, adapterUpdate: AdapterMetrics)
  {
    logger.debug("Received fallback IOKit update")

    var updatedBattery = newBatteryMetrics
    updatedBattery.batteryVoltage = fallbackMetrics.batteryVoltage
    updatedBattery.batteryCurrent = fallbackMetrics.batteryCurrent
    updatedBattery.batteryPower = fallbackMetrics.batteryPower
    fallbackMetrics = updatedBattery

    var updatedAdapter = adapterUpdate
    updatedAdapter.powerEnabled = fallbackAdapterMetrics.powerEnabled
    updatedAdapter.adapterVoltage = fallbackAdapterMetrics.adapterVoltage
    updatedAdapter.adapterCurrent = fallbackAdapterMetrics.adapterCurrent
    updatedAdapter.adapterPower = fallbackAdapterMetrics.adapterPower
    fallbackAdapterMetrics = updatedAdapter

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
  }

  private func applyFallbackSnapshot() {
    applyMetrics(fallbackMetrics, adapter: fallbackAdapterMetrics)
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

  private func synchronizeTelemetrySources() {
    let useDaemonTelemetry = telemetryRequested && authoritativeDaemonSnapshot != nil
    desiredDaemonTelemetry = useDaemonTelemetry

    if useDaemonTelemetry {
      stopFallbackFastPolling()
    } else if telemetryRequested {
      startFallbackFastPolling()
    } else {
      stopFallbackFastPolling()
    }

    startDaemonTelemetrySyncIfNeeded()
  }

  private func startFallbackFastPolling() {
    guard !fallbackFastPollingActive else { return }
    fallbackFastPollingActive = true
    smcPoller.start()
  }

  private func stopFallbackFastPolling() {
    guard fallbackFastPollingActive else { return }
    fallbackFastPollingActive = false
    smcPoller.stop()
  }

  private func startDaemonTelemetrySyncIfNeeded() {
    guard daemonTelemetrySyncTask == nil, desiredDaemonTelemetry != appliedDaemonTelemetry else {
      return
    }

    daemonTelemetrySyncTask = Task { [weak self] in
      guard let self else { return }

      while self.desiredDaemonTelemetry != self.appliedDaemonTelemetry {
        let target = self.desiredDaemonTelemetry
        do {
          try await self.daemonManager.setTelemetryActive(target)
          self.appliedDaemonTelemetry = target
        } catch {
          if !target {
            self.appliedDaemonTelemetry = false
          }
          self.logger.error(
            "Could not set daemon telemetry to \(target): \(error.localizedDescription)"
          )
          break
        }
      }

      self.daemonTelemetrySyncTask = nil
      if self.desiredDaemonTelemetry != self.appliedDaemonTelemetry,
        self.authoritativeDaemonSnapshot != nil
      {
        self.startDaemonTelemetrySyncIfNeeded()
      }
    }
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

  func manageBatteryCharging(enabled: Bool) async throws {
    try await ChargingDaemonManager.shared.executeCommand("manage battery charging") {
      helper, reply in
      helper.manageBatteryCharging(enabled: enabled) { success, errorMessage in
        reply(success, errorMessage)
      }
    }
  }

  func manageExternalPower(enabled: Bool) async throws {
    try await ChargingDaemonManager.shared.executeCommand("manage external power") {
      helper, reply in
      helper.manageExternalPower(enabled: enabled) { success, errorMessage in
        reply(success, errorMessage)
      }
    }
  }

  func manageMagsafeLED(target: MagSafeLEDState) async throws {
    try await ChargingDaemonManager.shared.executeCommand("manage MagSafe LED") { helper, reply in
      helper.manageMagsafeLED(target: target.rawValue) { success, errorMessage in
        reply(success, errorMessage)
      }
    }
  }

  func stop() {
    logger.info("BatteryService stopping")
    isStopped = true
    telemetryRequested = false
    desiredDaemonTelemetry = false
    daemonTelemetrySyncTask?.cancel()
    daemonTelemetrySyncTask = nil
    ioKitMonitorTask?.cancel()
    ioKitMonitorTask = nil
    smcPoller.shutdown()
  }
}
