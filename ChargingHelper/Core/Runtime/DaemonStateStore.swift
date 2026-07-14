import Foundation

actor DaemonStateStore {
    private let capabilities: DaemonCapabilities
    private let daemonVersion: String

    private var battery = DaemonBatterySnapshot()
    private var adapter = DaemonAdapterSnapshot()
    private var hardwareState = DaemonHardwareState()
    private var runtimeStatus: DaemonRuntimeStatus = .starting
    private var lastError: DaemonErrorPayload?

    private var chargeLimitOverrideActive = false
    private var forceDischargeActive = false
    private var desiredCharging: Bool?
    private var desiredAdapter: Bool?
    private var desiredLEDStateRawValue: UInt8?
    private var policyReason: String?

    init(
        capabilities: DaemonCapabilities,
        daemonVersion: String
    ) {
        self.capabilities = capabilities
        self.daemonVersion = daemonVersion
    }

    func setChargeLimitOverride(_ enabled: Bool) throws {
        guard capabilities.chargeLimitOverrideControl else {
            throw DaemonErrorPayload(
                code: .unsupported,
                message: "Charge-limit override is unsupported by this hardware"
            )
        }
        chargeLimitOverrideActive = enabled
        if enabled {
            forceDischargeActive = false
        }
    }

    func setForceDischarge(_ enabled: Bool) throws {
        guard capabilities.forceDischargeControl else {
            throw DaemonErrorPayload(
                code: .unsupported,
                message: "Force discharge is unsupported by this hardware"
            )
        }
        forceDischargeActive = enabled
        if enabled {
            chargeLimitOverrideActive = false
        }
    }

    func clearTemporaryPolicyState() {
        chargeLimitOverrideActive = false
        forceDischargeActive = false
    }

    func managementContext() -> DaemonManagementContext {
        DaemonManagementContext(
            controlState: BatteryControlState(
                batteryPercentage: battery.displayedPercentage,
                hardwareBatteryPercentage: battery.hardwarePercentage,
                adapterConnected: adapter.physicallyConnected,
                batteryTemperature: battery.temperature
            ),
            chargeLimitOverrideActive: chargeLimitOverrideActive,
            forceDischargeActive: forceDischargeActive
        )
    }

    func updatePolicyDecision(
        desiredCharging: Bool?,
        desiredAdapter: Bool?,
        desiredLEDStateRawValue: UInt8?,
        reason: String?
    ) {
        self.desiredCharging = desiredCharging
        self.desiredAdapter = desiredAdapter
        self.desiredLEDStateRawValue = desiredLEDStateRawValue
        policyReason = reason
    }

    @discardableResult
    func updatePowerSource(_ update: DaemonPowerSourceUpdate) -> Bool {
        let oldBattery = battery
        let oldAdapter = adapter
        battery = update.battery
        adapter = update.adapter
        return battery != oldBattery || adapter != oldAdapter
    }

    func updateHardwareState(_ state: DaemonHardwareState) {
        hardwareState = state
        adapter.powerEnabled = state.forceDischarging.map { !$0 }
        runtimeStatus = capabilities.chargingControl ? .ready : .unsupported
        lastError = nil
    }

    func recordHardwareError(_ error: Error) {
        hardwareState = DaemonHardwareState()
        adapter.powerEnabled = nil
        runtimeStatus = .degraded
        lastError = DaemonErrorPayload(
            code: .smcFailure,
            message: error.localizedDescription
        )
    }

    func snapshot(managementEnabled: Bool) -> DaemonSnapshot {
        return DaemonSnapshot(
            capabilities: capabilities,
            battery: battery,
            adapter: adapter,
            hardware: hardwareState,
            policy: DaemonPolicyState(
                managementEnabled: managementEnabled,
                chargeLimitOverrideActive: chargeLimitOverrideActive,
                forceDischargeActive: forceDischargeActive,
                desiredCharging: desiredCharging,
                desiredAdapter: desiredAdapter,
                desiredLEDStateRawValue: desiredLEDStateRawValue,
                reason: policyReason
            ),
            runtime: DaemonRuntimeState(
                status: runtimeStatus,
                daemonVersion: daemonVersion,
                updatedAt: Date(),
                lastError: lastError
            )
        )
    }
}
