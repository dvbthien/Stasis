import Foundation

actor DaemonStateStore {
    private let capabilities: DaemonCapabilities
    private let hardware: any DaemonHardwareControlling
    private let daemonVersion: String

    private var chargeLimitOverrideActive = false
    private var forceDischargeActive = false
    private var telemetryActive = false

    init(
        capabilities: DaemonCapabilities,
        hardware: any DaemonHardwareControlling,
        daemonVersion: String
    ) {
        self.capabilities = capabilities
        self.hardware = hardware
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

    func setTelemetryActive(_ active: Bool) {
        telemetryActive = active
    }

    func snapshot(settingsState: DaemonSettingsState) async -> DaemonSnapshot {
        let hardwareState: DaemonHardwareState
        let runtimeStatus: DaemonRuntimeStatus
        let lastError: DaemonErrorPayload?

        do {
            hardwareState = try await hardware.readHardwareState()
            runtimeStatus = capabilities.chargingControl ? .ready : .unsupported
            lastError = nil
        } catch {
            hardwareState = DaemonHardwareState()
            runtimeStatus = .degraded
            lastError = DaemonErrorPayload(
                code: .smcFailure,
                message: error.localizedDescription
            )
        }

        return DaemonSnapshot(
            capabilities: capabilities,
            battery: DaemonBatterySnapshot(),
            adapter: DaemonAdapterSnapshot(
                physicallyConnected: false,
                powerEnabled: hardwareState.forceDischarging.map { !$0 }
            ),
            hardware: hardwareState,
            policy: DaemonPolicyState(
                managementEnabled: settingsState.settings.managementEnabled,
                chargeLimitOverrideActive: chargeLimitOverrideActive,
                forceDischargeActive: forceDischargeActive,
                reason: "Daemon policy ownership is not enabled yet"
            ),
            runtime: DaemonRuntimeState(
                status: runtimeStatus,
                daemonVersion: daemonVersion,
                settingsRevision: settingsState.revision,
                updatedAt: Date(),
                lastError: lastError
            )
        )
    }
}
