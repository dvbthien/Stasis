import Foundation
import Observation
import os.log
import smc_power

/// Coordinates battery/adapter metrics from two independent sources — IOKit
/// (event-driven, owns the displayed battery %, health, temperature, etc.)
/// and the SMC helper via `SMCMetricsPoller` (polled, owns
/// voltage/current/power for the Sankey power diagram) — and merges them
/// into the single `metrics`/`adapterMetrics` the rest of the app observes.
///
/// This class deliberately does NOT touch `SMCReaderConnection` or any XPC
/// connection directly. All of that lifecycle — when to connect, when to
/// disconnect, what counts as "still in use" — is owned entirely by
/// `SMCMetricsPoller`. That used to be split across several methods here
/// (`loadCapabilities`, `disableFastPolling`), which is how a missed cleanup
/// call site let the helper process stay alive for hours.
@MainActor
@Observable
class BatteryService {
    var metrics = BatteryMetrics()
    var adapterMetrics = AdapterMetrics()
    private(set) var controlState = BatteryControlState()
    private(set) var deviceCapabilities = DeviceCapabilities.unknown

    private let ioKitService = IOKitService()
    private var smcPoller: SMCMetricsPoller!

    private var ioKitMonitorTask: Task<Void, Never>?

    private let logger = Logger.stasis("BatteryService")

    init() {
        logger.info("BatteryService initialized")
        smcPoller = SMCMetricsPoller(
            serviceName: "com.srimanachanta.stasis-monitor-helper",
            onReading: { [weak self] battery, adapter in
                self?.handleSMCReading(battery, adapter)
            }
        )
        // The XPC connection to the SMC helper is created lazily by
        // SMCMetricsPoller on first use, not eagerly here. The helper is an
        // on-demand XPC Service: holding a connection open for the app's
        // entire lifetime would keep that process alive continuously, even
        // when nothing is polling it.
        startIOKitMonitoring()
    }

    func loadCapabilities() async {
        guard let capabilities = await smcPoller.loadCapabilities() else {
            return
        }
        self.deviceCapabilities = capabilities
        logger.info(
            "Capabilities loaded: charging=\(capabilities.chargingControl), adapter=\(capabilities.adapterControl), magSafe=\(capabilities.hasMagSafe)"
        )
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
        smcPoller.start()
    }

    func disableFastPolling() {
        smcPoller.stop()
    }

    func scheduleSinglePoll(delay: Duration = .seconds(3)) {
        smcPoller.scheduleSinglePoll(delay: delay)
    }

    private func handleSMCReading(_ batteryReading: SMCBatteryReading, _ adapterReading: SMCAdapterReading) {
        var updatedBattery = metrics
        updatedBattery.batteryVoltage = batteryReading.batteryVoltage
        updatedBattery.batteryCurrent = batteryReading.batteryCurrent
        updatedBattery.batteryPower = batteryReading.batteryPower

        var updatedAdapter = adapterMetrics
        updatedAdapter.adapterVoltage = adapterReading.adapterVoltage
        updatedAdapter.adapterCurrent = adapterReading.adapterCurrent
        updatedAdapter.adapterPower = adapterReading.adapterPower

        // SMC reports faster than IOKit can update, so refine isCharging
        // using the actual power flow direction.
        if updatedAdapter.adapterConnected {
            updatedBattery.isCharging = batteryReading.batteryPower > 0
        }

        if updatedBattery != metrics {
            metrics = updatedBattery
        }
        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }
        updateControlState(from: updatedBattery, adapter: updatedAdapter)
    }

    private func handleIOKitUpdate(_ newBatteryMetrics: BatteryMetrics, adapterUpdate: AdapterMetrics) {
        logger.debug("Received IOKit update")

        var updatedBattery = newBatteryMetrics
        updatedBattery.batteryVoltage = metrics.batteryVoltage
        updatedBattery.batteryCurrent = metrics.batteryCurrent
        updatedBattery.batteryPower = metrics.batteryPower

        if updatedBattery != metrics {
            metrics = updatedBattery
        }

        var updatedAdapter = adapterUpdate
        updatedAdapter.adapterVoltage = adapterMetrics.adapterVoltage
        updatedAdapter.adapterCurrent = adapterMetrics.adapterCurrent
        updatedAdapter.adapterPower = adapterMetrics.adapterPower

        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }

        updateControlState(from: updatedBattery, adapter: updatedAdapter)
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
        let helper = try getChargingHelper()
        try await withCheckedThrowingContinuation { continuation in
            helper.manageBatteryCharging(enabled: enabled) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: XPCError.commandFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    func manageExternalPower(enabled: Bool) async throws {
        let helper = try getChargingHelper()
        try await withCheckedThrowingContinuation { continuation in
            helper.manageExternalPower(enabled: enabled) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: XPCError.commandFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    func manageMagsafeLED(target: MagSafeLEDState) async throws {
        let helper = try getChargingHelper()
        try await withCheckedThrowingContinuation { continuation in
            helper.manageMagsafeLED(target: target.rawValue) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: XPCError.commandFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    private func getChargingHelper() throws -> ChargingHelperProtocol {
        let logger = self.logger
        guard
            let helper = ChargingDaemonManager.shared.getHelper(errorHandler: { error in
                logger.error("Charging helper XPC error: \(error.localizedDescription)")
            })
        else {
            throw XPCError.helperUnavailable
        }
        return helper
    }

    func stop() {
        logger.info("BatteryService stopping")
        ioKitMonitorTask?.cancel()
        ioKitMonitorTask = nil
        smcPoller.shutdown()
    }
}
