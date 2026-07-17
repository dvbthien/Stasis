import Foundation

/// Fallback when no charge-control SMC keys exist. It never touches charging
/// hardware; it only records policy decisions so clients can explain why
/// management is inactive. Adapter restore is still attempted on shutdown to
/// match the engine's historical behavior on capability-probed hardware.
actor UnsupportedChargeControlStrategy: ChargeControlStrategizing {
    private let capabilities: DaemonCapabilities
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling

    init(
        capabilities: DaemonCapabilities,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling
    ) {
        self.capabilities = capabilities
        self.stateStore = stateStore
        self.hardware = hardware
    }

    func reconcileManagement(
        context _: DaemonManagementContext,
        stateWasCleared _: Bool
    ) async throws -> Bool {
        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: nil,
            desiredLEDStateRawValue: nil,
            reason: "Charge control is unsupported"
        )
        return false
    }

    func applySystemDefaults(reason: String) async throws -> Bool {
        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: capabilities.magSafeLEDControl ? 0 : nil,
            reason: reason
        )
        return false
    }

    func restoreHardwareDefaults(reason: String) async throws -> Bool {
        var powerPathChanged = false
        if capabilities.adapterControl {
            powerPathChanged = try await hardware.setAdapterEnabled(true)
        }
        await stateStore.updatePolicyDecision(
            desiredCharging: nil,
            desiredAdapter: capabilities.adapterControl ? true : nil,
            desiredLEDStateRawValue: nil,
            reason: reason
        )
        return powerPathChanged
    }
}
