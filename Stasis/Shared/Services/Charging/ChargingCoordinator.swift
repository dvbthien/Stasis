import Defaults
import Foundation
import Observation
import os.log
import smc_power

/// Coordinates automatic battery charge management: watches battery/adapter
/// metrics and user settings, asks the charging policies what the hardware
/// should be doing, and applies that decision through `BatteryService`.
///
/// `ChargingCoordinator` itself only orchestrates — it doesn't contain the rules
/// for *what* to decide (see `ChargeLimitPolicy`, `HeatProtectionPolicy`,
/// `ForceDischargePolicy`) or the mechanics of sleep assertions and
/// notifications (see `SleepAssertionController`, `ChargingStateNotifier`).
/// That split is what keeps `evaluate` readable as a short pipeline instead
/// of one long conditional chain.
@MainActor
@Observable
class ChargingCoordinator {
    private let batteryService: BatteryService

    private var metricsObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?

    private var lastAdapterConnected: Bool?
    private var lastManageChargingEnabled: Bool?
    private var hasReachedChargeLimit = false

    private(set) var chargeLimitOverrideActive = false
    private(set) var forceDischargeActive = false

    private let sleepAssertion = SleepAssertionController()
    private let notifier = ChargingStateNotifier()

    private let logger = Logger.stasis("ChargingCoordinator")

    init(batteryService: BatteryService) {
        self.batteryService = batteryService
        startObservingMetrics()
        startObservingSettings()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.evaluate(controlState: self.batteryService.controlState)
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.controlState
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .manageCharging, .sailingMode, .automaticDischarge,
                    .disableSleepUntilChargeLimit,
                    .enableHeatProtectionMode, .manageMagSafeLED, .useHardwarePercentage,
                    .chargeLimit, .sailingModeLimit, .heatProtectionLimit,
                    .heatProtectionMagSafeLEDState,
                ],
                initial: false
            ) {
                guard let self else { return }
                self.evaluate(controlState: self.batteryService.controlState)
            }
        }
    }

    /// One evaluation pass: figure out what the hardware should be doing
    /// right now, and apply it. Reads as a short pipeline — detect
    /// transitions, bail out if management isn't applicable, ask the
    /// policies for a decision, apply it — with each step's detail living
    /// in its own method or type rather than inline here.
    private func evaluate(controlState: BatteryControlState) {
        var stateWasCleared = handleAdapterConnectionChange(controlState)

        guard Defaults[.manageCharging], controlState.adapterConnected else {
            handleManagementUnavailable(adapterConnected: controlState.adapterConnected)
            return
        }

        if lastManageChargingEnabled != true {
            lastManageChargingEnabled = true
            clearCachedState()
            stateWasCleared = true
        }

        let settings = ChargingSettingsSnapshot(chargeLimitOverrideActive: chargeLimitOverrideActive)

        var decision = ChargeLimitPolicy.evaluate(
            controlState: controlState,
            settings: settings,
            stateWasCleared: stateWasCleared,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )
        HeatProtectionPolicy.apply(to: &decision, controlState: controlState, settings: settings)
        ForceDischargePolicy.apply(to: &decision, isActive: forceDischargeActive)

        apply(decision: decision, settings: settings)
    }

    /// Detects an adapter plug/unplug transition and clears state that's no
    /// longer valid across it. Returns whether such a transition happened,
    /// which both the limit policy (hysteresis priming) and `evaluate`
    /// (re-clearing on re-enable) need to know about.
    private func handleAdapterConnectionChange(_ controlState: BatteryControlState) -> Bool {
        guard controlState.adapterConnected != lastAdapterConnected else { return false }
        logger.info("Adapter connection changed: \(controlState.adapterConnected)")
        lastAdapterConnected = controlState.adapterConnected
        clearCachedState()
        return true
    }

    /// Charging management is off or the adapter is unplugged: drop any
    /// transient overrides that only make sense while plugged in, and hand
    /// control back to macOS.
    private func handleManagementUnavailable(adapterConnected: Bool) {
        if chargeLimitOverrideActive, !adapterConnected {
            chargeLimitOverrideActive = false
        }
        if forceDischargeActive, !adapterConnected {
            forceDischargeActive = false
        }
        resetToDefaults()
    }

    /// Turns a computed decision into actual hardware commands, gated by
    /// what this device's helper reports it can actually control.
    private func apply(decision: ChargingDecision, settings: ChargingSettingsSnapshot) {
        let capabilities = batteryService.deviceCapabilities

        if let desiredCharging = decision.desiredCharging, capabilities.chargingControl {
            setCharging(enabled: desiredCharging)
            notifier.notifyIfChanged(charging: desiredCharging, reason: decision.reason)
        }
        if let desiredAdapter = decision.desiredAdapter, capabilities.adapterControl {
            setAdapter(enabled: desiredAdapter)
        }
        if let desiredLED = decision.desiredLED, capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            setLED(state: desiredLED)
        }

        let shouldPreventSleep = settings.disableSleepUntilChargeLimit && decision.desiredCharging == true
        sleepAssertion.update(shouldPreventSleep: shouldPreventSleep)
    }

    private func clearCachedState() {
        notifier.reset()
        hasReachedChargeLimit = false
    }

    private func resetToDefaults() {
        hasReachedChargeLimit = false
        lastManageChargingEnabled = false
        sleepAssertion.update(shouldPreventSleep: false)
        guard ChargingDaemonManager.shared.isInstalled else { return }
        let capabilities = batteryService.deviceCapabilities
        if capabilities.chargingControl {
            setCharging(enabled: true)
        }
        if capabilities.adapterControl {
            setAdapter(enabled: true)
        }
        if capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            setLED(state: .reset)
        }
    }

    /// Fires a hardware command asynchronously and logs on failure.
    /// Commands are best-effort from `ChargingCoordinator`'s perspective.
    /// If one fails transiently, the next evaluation pass can compute the
    /// same decision again and retry; the failure is also forwarded to
    /// Settings so the user can see the daemon's runtime state.
    ///
    /// Pulled out because `setCharging`, `setAdapter`, and `setLED` used to
    /// each repeat the same "log, wrap in `Task`, `do`/`catch`, log the
    /// error" shape with nothing but the log strings differing.
    private func runCommand(
        _ label: String,
        refreshMetricsAfterSuccess: Bool = false,
        action: @escaping () async throws -> Void
    ) {
        logger.info("\(label)")
        Task {
            do {
                try await action()
                if refreshMetricsAfterSuccess {
                    self.batteryService.scheduleSinglePoll()
                }
            } catch {
                logger.error("\(label) failed: \(error)")
                ChargingDaemonManager.shared.recordRuntimeError(error, while: label)
            }
        }
    }

    private func setCharging(enabled: Bool) {
        runCommand("Setting charging: \(enabled)", refreshMetricsAfterSuccess: true) {
            try await self.batteryService.manageBatteryCharging(enabled: enabled)
        }
    }

    private func setAdapter(enabled: Bool) {
        runCommand("Setting adapter: \(enabled)", refreshMetricsAfterSuccess: true) {
            try await self.batteryService.manageExternalPower(enabled: enabled)
        }
    }

    private func setLED(state: MagSafeLEDState) {
        runCommand("Setting MagSafe LED: \(String(describing: state))") {
            try await self.batteryService.manageMagsafeLED(target: state)
        }
    }

    func toggleChargeLimitOverride() {
        let shouldActivate = !chargeLimitOverrideActive
        chargeLimitOverrideActive = shouldActivate
        if shouldActivate {
            forceDischargeActive = false
            clearCachedState()
        }
        evaluate(controlState: batteryService.controlState)
    }

    func toggleForceDischarge() {
        let shouldActivate = !forceDischargeActive
        forceDischargeActive = shouldActivate
        if shouldActivate {
            chargeLimitOverrideActive = false
        }
        evaluate(controlState: batteryService.controlState)
    }

    func stop() {
        metricsObservation?.cancel()
        metricsObservation = nil
        settingsObservation?.cancel()
        settingsObservation = nil
        sleepAssertion.update(shouldPreventSleep: false)
    }
}
