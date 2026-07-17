import Foundation
import os.log

struct DaemonManagementContext: Sendable {
    let controlState: BatteryControlState
    let chargeLimitOverrideActive: Bool
    let forceDischargeActive: Bool
}

/// Owns the reconcile lifecycle: event routing, temporary-state bookkeeping,
/// error retry, and snapshot publication. All mode-specific hardware logic
/// lives in the `ChargeControlStrategizing` implementations.
actor BatteryManagementEngine {
    private let mode: ChargeControlMode
    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let strategy: any ChargeControlStrategizing
    private let reconcileQueue: DaemonReconcileQueue
    private let retryDelay: Duration

    private var previousAdapterConnected: Bool?
    private var previousManagementEnabled: Bool?
    private var uninstallError: DaemonErrorPayload?
    private var isPreparedForUninstall = false

    private let logger = Logger(
        subsystem: Constants.Identity.daemon,
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
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.reconcileQueue = reconcileQueue
        self.retryDelay = retryDelay
        strategy = Self.makeStrategy(
            capabilities: capabilities,
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            sleepAssertion: sleepAssertion
        )
    }

    private static func makeStrategy(
        capabilities: DaemonCapabilities,
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        sleepAssertion: any DaemonSleepAssertionControlling
    ) -> any ChargeControlStrategizing {
        switch capabilities.chargeControlMode {
        case .legacy:
            LegacyChargeControlStrategy(
                capabilities: capabilities,
                settingsStore: settingsStore,
                stateStore: stateStore,
                hardware: hardware,
                sleepAssertion: sleepAssertion
            )
        case .firmware:
            FirmwareChargeControlStrategy(
                capabilities: capabilities,
                settingsStore: settingsStore,
                stateStore: stateStore,
                hardware: hardware
            )
        case .unsupported:
            UnsupportedChargeControlStrategy(
                capabilities: capabilities,
                stateStore: stateStore,
                hardware: hardware
            )
        }
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
        let context = await stateStore.managementContext()
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
                powerPathChanged = try await strategy.applySystemDefaults(
                    reason: management.isEnabled
                        ? "Power adapter is disconnected"
                        : "Battery management is disabled"
                )
            } else {
                powerPathChanged = try await strategy.reconcileManagement(
                    context: context,
                    stateWasCleared: stateWasCleared
                )
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

    private func restoreHardwareDefaults(reason: String) async throws -> Bool {
        await stateStore.clearTemporaryPolicyState()
        return try await strategy.restoreHardwareDefaults(reason: reason)
    }
}
