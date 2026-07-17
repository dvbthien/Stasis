import Foundation

/// Software-enforced charge control for pre-Tahoe (`CH0B`/`CH0C`) and Tahoe
/// (`CHTE`) firmware. The daemon owns the control loop: it evaluates the pure
/// charging policies and drives charging, adapter, MagSafe LED, and the sleep
/// assertion accordingly.
actor LegacyChargeControlStrategy: ChargeControlStrategizing {
    private let capabilities: DaemonCapabilities
    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let sleepAssertion: any DaemonSleepAssertionControlling

    private var hasReachedChargeLimit = false
    private var adapterWasForceDisabled = false
    private var hasManagedMagSafeLED = false

    init(
        capabilities: DaemonCapabilities,
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        sleepAssertion: any DaemonSleepAssertionControlling
    ) {
        self.capabilities = capabilities
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.sleepAssertion = sleepAssertion
    }

    func reconcileManagement(
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

    func applySystemDefaults(reason: String) async throws -> Bool {
        hasReachedChargeLimit = false
        await sleepAssertion.update(shouldPreventSleep: false)

        var powerPathChanged = try await hardware.setChargingEnabled(true)
        if capabilities.adapterControl {
            powerPathChanged =
                try await hardware.setAdapterEnabled(true)
                || powerPathChanged
        }
        if capabilities.magSafeLEDControl {
            _ = try await hardware.setMagSafeLED(rawValue: 0)
        }
        adapterWasForceDisabled = false

        await stateStore.updatePolicyDecision(
            desiredCharging: true,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: capabilities.magSafeLEDControl ? 0 : nil,
            reason: reason
        )
        return powerPathChanged
    }

    func restoreHardwareDefaults(reason: String) async throws -> Bool {
        hasReachedChargeLimit = false
        await sleepAssertion.update(shouldPreventSleep: false)

        var powerPathChanged = try await hardware.setChargingEnabled(true)
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
            desiredCharging: true,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: didResetMagSafeLED ? 0 : nil,
            reason: reason
        )
        return powerPathChanged
    }
}
