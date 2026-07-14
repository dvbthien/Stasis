import Foundation
import os.log

struct DaemonManagementContext: Sendable {
    let controlState: BatteryControlState
    let chargeLimitOverrideActive: Bool
    let forceDischargeActive: Bool
}

actor BatteryManagementEngine {
    private let mode: ChargeControlMode
    private let capabilities: DaemonCapabilities
    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let sleepAssertion: any DaemonSleepAssertionControlling
    private let reconcileQueue: DaemonReconcileQueue
    private let retryDelay: Duration

    private var previousAdapterConnected: Bool?
    private var previousManagementEnabled: Bool?
    private var hasReachedChargeLimit = false
    private var adapterWasForceDisabled = false
    private var hasManagedMagSafeLED = false
    private var uninstallError: DaemonErrorPayload?
    private var isPreparedForUninstall = false

    private let logger = Logger(
        subsystem: "com.srimanachanta.stasis-daemon",
        category: "BatteryManagementEngine"
    )

    init(
        capabilities: DaemonCapabilities,
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        sleepAssertion: any DaemonSleepAssertionControlling = DaemonSleepAssertionController(),
        reconcileQueue: DaemonReconcileQueue = DaemonReconcileQueue(),
        retryDelay: Duration = .seconds(2)
    ) {
        mode = capabilities.chargeControlMode
        self.capabilities = capabilities
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.sleepAssertion = sleepAssertion
        self.reconcileQueue = reconcileQueue
        self.retryDelay = retryDelay
    }

    func start() async {
        await reconcileQueue.start { [weak self] events in
            await self?.reconcile(events: events) ?? .noPublication
        }
    }

    func reconcilePolicy(on event: DaemonPolicyEvent) async -> DaemonPolicyReconcileResult {
        await reconcileQueue.request(event)
    }

    func setChargeLimitOverride(_ enabled: Bool) async throws -> DaemonPolicyReconcileResult {
        try await stateStore.setChargeLimitOverride(enabled)
        return await reconcilePolicy(on: .temporaryCommand)
    }

    func setForceDischarge(_ enabled: Bool) async throws -> DaemonPolicyReconcileResult {
        try await stateStore.setForceDischarge(enabled)
        return await reconcilePolicy(on: .temporaryCommand)
    }

    func prepareForUninstall() async throws -> DaemonPolicyReconcileResult {
        isPreparedForUninstall = true
        uninstallError = nil
        let result = await reconcilePolicy(on: .uninstall)
        if let uninstallError {
            isPreparedForUninstall = false
            throw uninstallError
        }
        return result
    }

    func cancelUninstallPreparation() async -> DaemonPolicyReconcileResult {
        guard isPreparedForUninstall else { return .noPublication }
        isPreparedForUninstall = false
        return await reconcilePolicy(on: .startup)
    }

    /// Stops scheduling work and restores every SMC state managed by the daemon
    /// before launchd terminates the process.
    func shutdown() async {
        _ = await reconcilePolicy(on: .shutdown)
        await reconcileQueue.stop()
    }

    private func reconcile(events: Set<DaemonPolicyEvent>) async -> DaemonPolicyReconcileResult {
        let management = await settingsStore.chargingManagementSettings()
        var context = await stateStore.managementContext()
        let stateWasCleared =
            previousAdapterConnected != context.controlState.adapterConnected
            || previousManagementEnabled != true
        previousAdapterConnected = context.controlState.adapterConnected
        previousManagementEnabled = management.isEnabled
        var powerPathChanged = false

        do {
            if events.contains(.shutdown) {
                powerPathChanged = try await restoreHardwareDefaults(
                    reason: "Daemon is shutting down"
                )
            } else if isPreparedForUninstall || events.contains(.uninstall) {
                powerPathChanged = try await restoreHardwareDefaults(
                    reason: "Daemon prepared for uninstall"
                )
            } else if !management.isEnabled || !context.controlState.adapterConnected {
                await stateStore.clearTemporaryPolicyState()
                context = await stateStore.managementContext()
                hasReachedChargeLimit = false
                powerPathChanged = try await applySystemDefaults(
                    reason: management.isEnabled
                        ? "Power adapter is disconnected"
                        : "Battery management is disabled"
                )
            } else {
                switch mode {
                case .legacy:
                    powerPathChanged = try await reconcileLegacy(
                        context: context,
                        stateWasCleared: stateWasCleared
                    )
                case .firmware:
                    powerPathChanged = try await reconcileFirmware(context: context)
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
                "Policy reconcile mode=\(self.mode.rawValue, privacy: .public) events=\(events.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)"
            )
        } catch {
            if events.contains(.uninstall) {
                uninstallError = DaemonErrorPayload(
                    code: .smcFailure,
                    message: error.localizedDescription
                )
            }
            await stateStore.recordHardwareError(error)
            logger.error("Policy reconcile failed: \(error.localizedDescription, privacy: .public)")
            if !events.contains(.shutdown) {
                await reconcileQueue.scheduleRetry(after: retryDelay)
            }
        }

        if events.contains(.shutdown) {
            return .noPublication
        }

        if powerPathChanged {
            return .publishAfterPowerPathChange
        }
        return .publishSnapshot
    }

    private func reconcileLegacy(
        context: DaemonManagementContext,
        stateWasCleared: Bool
    ) async throws -> Bool {
        let policySettings = await settingsStore.makePolicyInput(
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
            hasManagedMagSafeLED = true
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
        context: DaemonManagementContext
    ) async throws -> Bool {
        let settings = await settingsStore.chargingThresholdSettings()
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

    private func restoreHardwareDefaults(reason: String) async throws -> Bool {
        await stateStore.clearTemporaryPolicyState()
        hasReachedChargeLimit = false
        await sleepAssertion.update(shouldPreventSleep: false)

        var powerPathChanged = false
        switch mode {
        case .legacy:
            powerPathChanged =
                try await hardware.setChargingEnabled(true)
                || powerPathChanged
        case .firmware:
            powerPathChanged =
                try await hardware.ensureFirmwareChargeLimitDisabled()
                || powerPathChanged
        case .unsupported:
            break
        }

        if capabilities.adapterControl {
            powerPathChanged =
                try await hardware.setAdapterEnabled(true)
                || powerPathChanged
        }
        adapterWasForceDisabled = false

        let didResetMagSafeLED = hasManagedMagSafeLED && capabilities.magSafeLEDControl
        if didResetMagSafeLED {
            _ = try await hardware.setMagSafeLED(rawValue: 0)
            hasManagedMagSafeLED = false
        }

        await stateStore.updatePolicyDecision(
            desiredCharging: mode == .legacy ? true : nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: didResetMagSafeLED ? 0 : nil,
            reason: reason
        )
        return powerPathChanged
    }
}
