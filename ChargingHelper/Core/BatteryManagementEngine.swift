import Foundation
import os.log
import smc_power

struct DaemonManagementContext: Sendable {
    let controlState: BatteryControlState
    let chargeLimitOverrideActive: Bool
    let forceDischargeActive: Bool
}

actor BatteryManagementEngine {
    private let mode: ChargeControlMode
    private let capabilities: DaemonCapabilities
    private let settingsStore: DaemonSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let sleepAssertion: any DaemonSleepAssertionControlling
    private let maintainLoop: DaemonMaintainLoop
    private weak var runtime: DaemonRuntimeCoordinator?
    private let periodicInterval: Duration
    private let retryDelay: Duration

    private var previousAdapterConnected: Bool?
    private var previousManagementEnabled: Bool?
    private var hasReachedChargeLimit = false
    private var adapterWasForceDisabled = false

    private let logger = Logger(
        subsystem: "com.srimanachanta.stasis-daemon",
        category: "BatteryManagementEngine"
    )

    init(
        capabilities: DaemonCapabilities,
        settingsStore: DaemonSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        runtime: DaemonRuntimeCoordinator,
        sleepAssertion: any DaemonSleepAssertionControlling = DaemonSleepAssertionController(),
        maintainLoop: DaemonMaintainLoop = DaemonMaintainLoop(),
        periodicInterval: Duration = .seconds(10),
        retryDelay: Duration = .seconds(2)
    ) {
        mode = capabilities.chargeControlMode
        self.capabilities = capabilities
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.runtime = runtime
        self.sleepAssertion = sleepAssertion
        self.maintainLoop = maintainLoop
        self.periodicInterval = periodicInterval
        self.retryDelay = retryDelay
    }

    func start() async {
        await maintainLoop.start(periodicInterval: periodicInterval) { [weak self] reasons in
            await self?.reconcile(reasons: reasons)
        }
    }

    func request(_ reason: DaemonMaintainReason) async {
        await maintainLoop.request(reason)
    }

    func setChargeLimitOverride(_ enabled: Bool) async throws {
        try await stateStore.setChargeLimitOverride(enabled)
        await request(.temporaryCommand)
    }

    func setForceDischarge(_ enabled: Bool) async throws {
        try await stateStore.setForceDischarge(enabled)
        await request(.temporaryCommand)
    }

    /// Stops scheduling work and releases only process-owned resources.
    /// Hardware state is intentionally preserved across daemon termination.
    func shutdown() async {
        await maintainLoop.stop()
        if mode == .legacy {
            await sleepAssertion.update(shouldPreventSleep: false)
        }
    }

    private func reconcile(reasons: Set<DaemonMaintainReason>) async {
        let settingsState = await settingsStore.state()
        let settings = settingsState.settings
        var context = await stateStore.managementContext()
        let stateWasCleared =
            previousAdapterConnected != context.controlState.adapterConnected
            || previousManagementEnabled != true
        previousAdapterConnected = context.controlState.adapterConnected
        previousManagementEnabled = settings.managementEnabled
        var powerPathChanged = false

        do {
            if !settings.managementEnabled || !context.controlState.adapterConnected {
                await stateStore.clearTemporaryPolicyState()
                context = await stateStore.managementContext()
                hasReachedChargeLimit = false
                powerPathChanged = try await applySystemDefaults(
                    reason: settings.managementEnabled
                        ? "Power adapter is disconnected"
                        : "Battery management is disabled"
                )
            } else {
                switch mode {
                case .legacy:
                    powerPathChanged = try await reconcileLegacy(
                        settings: settings,
                        context: context,
                        stateWasCleared: stateWasCleared
                    )
                case .firmware:
                    powerPathChanged = try await reconcileFirmware(
                        settings: settings,
                        context: context
                    )
                case .unsupported:
                    await stateStore.updatePolicyDecision(
                        desiredCharging: nil,
                        desiredAdapter: nil,
                        desiredLEDStateRawValue: nil,
                        reason: "Charge control is unsupported"
                    )
                }
            }

            await stateStore.updateHardwareState(try await hardware.readHardwareState())
            logger.debug(
                "Maintain pass mode=\(self.mode.rawValue, privacy: .public) triggers=\(reasons.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)"
            )
        } catch {
            await stateStore.recordHardwareError(error)
            logger.error("Maintain pass failed: \(error.localizedDescription, privacy: .public)")
            await maintainLoop.scheduleRetry(after: retryDelay)
        }

        if powerPathChanged {
            await runtime?.refreshTelemetryAfterPolicyApply()
        } else {
            await runtime?.publishCurrentSnapshot()
        }
    }

    private func reconcileLegacy(
        settings: DaemonSettings,
        context: DaemonManagementContext,
        stateWasCleared: Bool
    ) async throws -> Bool {
        let policySettings = ChargingSettingsSnapshot(
            settings: settings,
            chargeLimitOverrideActive: context.chargeLimitOverrideActive
        )
        var decision = ChargeLimitPolicy.evaluate(
            controlState: context.controlState,
            settings: policySettings,
            stateWasCleared: stateWasCleared,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )
        HeatProtectionPolicy.apply(
            to: &decision,
            controlState: context.controlState,
            settings: policySettings
        )
        ForceDischargePolicy.apply(
            to: &decision,
            isActive: context.forceDischargeActive
        )

        var powerPathChanged = false
        if let desiredCharging = decision.desiredCharging {
            powerPathChanged =
                try await hardware.setChargingEnabled(desiredCharging)
                || powerPathChanged
        }
        if let desiredAdapter = decision.desiredAdapter, capabilities.adapterControl {
            powerPathChanged =
                try await hardware.setAdapterEnabled(desiredAdapter)
                || powerPathChanged
            adapterWasForceDisabled = !desiredAdapter
        }
        if let desiredLED = decision.desiredLED, capabilities.magSafeLEDControl {
            _ = try await hardware.setMagSafeLED(rawValue: desiredLED.rawValue)
        }

        await sleepAssertion.update(
            shouldPreventSleep: policySettings.disableSleepUntilChargeLimit
                && decision.desiredCharging == true
        )
        await stateStore.updatePolicyDecision(
            desiredCharging: decision.desiredCharging,
            desiredAdapter: decision.desiredAdapter,
            desiredLEDStateRawValue: decision.desiredLED?.rawValue,
            reason: decision.reason
        )
        return powerPathChanged
    }

    private func reconcileFirmware(
        settings: DaemonSettings,
        context: DaemonManagementContext
    ) async throws -> Bool {
        var powerPathChanged = false
        if context.forceDischargeActive {
            powerPathChanged =
                try await hardware.ensureFirmwareChargeLimitDisabled()
                || powerPathChanged
            powerPathChanged =
                try await hardware.setAdapterEnabled(false)
                || powerPathChanged
            adapterWasForceDisabled = true
            await stateStore.updatePolicyDecision(
                desiredCharging: nil,
                desiredAdapter: false,
                desiredLEDStateRawValue: nil,
                reason: "Manual force discharge is active"
            )
            return powerPathChanged
        }

        if adapterWasForceDisabled {
            powerPathChanged =
                try await hardware.setAdapterEnabled(true)
                || powerPathChanged
            adapterWasForceDisabled = false
        }

        let upper = context.chargeLimitOverrideActive ? 100 : settings.chargeLimit
        if upper == 100 {
            powerPathChanged =
                try await hardware.ensureFirmwareChargeLimitDisabled()
                || powerPathChanged
        } else {
            let requestedDelta = settings.sailingModeEnabled ? settings.sailingDelta : 1
            let lower = upper - max(1, requestedDelta)
            powerPathChanged =
                try await hardware.ensureFirmwareChargeLimit(lower: lower, upper: upper)
                || powerPathChanged
        }

        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: nil,
            desiredLEDStateRawValue: nil,
            reason: context.chargeLimitOverrideActive
                ? "Firmware charge limit is temporarily disabled"
                : "Firmware is enforcing the charge limit"
        )
        return powerPathChanged
    }

    private func applySystemDefaults(reason: String) async throws -> Bool {
        var powerPathChanged = false
        switch mode {
        case .legacy:
            await sleepAssertion.update(shouldPreventSleep: false)
            powerPathChanged =
                try await hardware.setChargingEnabled(true)
                || powerPathChanged
            if capabilities.adapterControl {
                powerPathChanged =
                    try await hardware.setAdapterEnabled(true)
                    || powerPathChanged
            }
            if capabilities.magSafeLEDControl {
                _ = try await hardware.setMagSafeLED(rawValue: 0)
            }
        case .firmware:
            powerPathChanged =
                try await hardware.ensureFirmwareChargeLimitDisabled()
                || powerPathChanged
            if adapterWasForceDisabled, capabilities.adapterControl {
                powerPathChanged =
                    try await hardware.setAdapterEnabled(true)
                    || powerPathChanged
            }
        case .unsupported:
            break
        }
        adapterWasForceDisabled = false
        await stateStore.updatePolicyDecision(
            desiredCharging: mode == .legacy ? true : nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: capabilities.magSafeLEDControl ? 0 : nil,
            reason: reason
        )
        return powerPathChanged
    }
}
