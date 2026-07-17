import Foundation

/// Firmware-enforced charge control for macOS 27-era SMCs (`bfF0`/`bfD0`/
/// `bfE0`). The firmware owns hysteresis — including during sleep — so this
/// strategy is a thin reconciler: it programs the limit window and deliberately
/// leaves sleep, MagSafe, and heat-protection management alone.
actor FirmwareChargeControlStrategy: ChargeControlStrategizing {
    private let capabilities: DaemonCapabilities
    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling

    private var adapterWasForceDisabled = false

    init(
        capabilities: DaemonCapabilities,
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling
    ) {
        self.capabilities = capabilities
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
    }

    func reconcileManagement(
        context: DaemonManagementContext,
        stateWasCleared _: Bool
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

    func applySystemDefaults(reason: String) async throws -> Bool {
        var powerPathChanged = try await hardware.ensureFirmwareChargeLimitDisabled()
        if adapterWasForceDisabled, capabilities.adapterControl {
            powerPathChanged =
                try await hardware.setAdapterEnabled(true)
                || powerPathChanged
        }
        adapterWasForceDisabled = false

        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: capabilities.magSafeLEDControl ? 0 : nil,
            reason: reason
        )
        return powerPathChanged
    }

    func restoreHardwareDefaults(reason: String) async throws -> Bool {
        var powerPathChanged = try await hardware.ensureFirmwareChargeLimitDisabled()
        if capabilities.adapterControl {
            powerPathChanged =
                try await hardware.setAdapterEnabled(true)
                || powerPathChanged
        }
        adapterWasForceDisabled = false

        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: nil,
            reason: reason
        )
        return powerPathChanged
    }
}
