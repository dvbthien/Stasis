import Foundation

actor DaemonRuntimeCoordinator {
    typealias IOKitRefreshHandler = @Sendable (
        DaemonPowerSourceUpdateReason
    ) async -> DaemonPowerSourceUpdate?

    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let clients: DaemonClientRegistry

    private var managementEngine: BatteryManagementEngine?
    private var ioKitRefreshHandler: IOKitRefreshHandler?

    init(
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        clients: DaemonClientRegistry
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.clients = clients
    }

    func installManagementEngine(_ engine: BatteryManagementEngine) async {
        managementEngine = engine
        await engine.start()
    }

    func installIOKitRefreshHandler(_ handler: @escaping IOKitRefreshHandler) {
        ioKitRefreshHandler = handler
    }

    func handlePowerSourceUpdate(_ update: DaemonPowerSourceUpdate) async {
        _ = await stateStore.updatePowerSource(update)

        if update.reason == .initial || update.reason == .wake {
            await refreshHardwareState()
            await publishCurrentSnapshot()
        } else {
            await publishCurrentSnapshot()
        }

        let policyEvent: DaemonPolicyEvent =
            switch update.reason {
            case .initial: .startup
            case .interestNotification: .powerSource
            case .wake: .wake
            case .settingsRefresh, .hardwareRefresh: .powerSource
            }
        await reconcilePolicy(on: policyEvent)
    }

    func currentSnapshot(refreshHardware: Bool = true) async -> DaemonSnapshot {
        if refreshHardware {
            await refreshHardwareState()
        }
        let management = await settingsStore.chargingManagementSettings()
        return await stateStore.snapshot(managementEnabled: management.isEnabled)
    }

    func publishCurrentSnapshot(refreshHardware: Bool = false) async {
        let snapshot = await currentSnapshot(refreshHardware: refreshHardware)
        guard let payload = try? DaemonPayloadCodec.encode(snapshot) else { return }
        clients.publishSnapshot(payload)
    }

    func reconcilePolicyAfterHardwareCommand() async {
        _ = await refreshIOKitSnapshot(reason: .hardwareRefresh)
        await publishCurrentSnapshot(refreshHardware: true)
        await reconcilePolicy(on: .hardwareCommand)
    }

    /// Publishes state after policy reconciliation has already applied
    /// hardware state. This deliberately does not enqueue another policy event.
    private func publishSnapshotAfterPolicyReconcile() async {
        _ = await refreshIOKitSnapshot(reason: .hardwareRefresh)
        await publishCurrentSnapshot()
    }

    func reconcilePolicyAfterSettingsChange() async {
        _ = await refreshIOKitSnapshot(reason: .settingsRefresh)
        await reconcilePolicy(on: .settings)
    }

    func setChargeLimitOverride(_ enabled: Bool) async throws -> DaemonSnapshot {
        guard let managementEngine else {
            throw DaemonErrorPayload(
                code: .internalFailure,
                message: "Battery management engine is unavailable"
            )
        }
        let result = try await managementEngine.setChargeLimitOverride(enabled)
        await publishPolicyReconcileResult(result)
        return await currentSnapshot(refreshHardware: false)
    }

    func setForceDischarge(_ enabled: Bool) async throws -> DaemonSnapshot {
        guard let managementEngine else {
            throw DaemonErrorPayload(
                code: .internalFailure,
                message: "Battery management engine is unavailable"
            )
        }
        let result = try await managementEngine.setForceDischarge(enabled)
        await publishPolicyReconcileResult(result)
        return await currentSnapshot(refreshHardware: false)
    }

    func prepareForUninstall() async throws {
        guard let managementEngine else {
            throw DaemonErrorPayload(
                code: .internalFailure,
                message: "Battery management engine is unavailable"
            )
        }
        let result = try await managementEngine.prepareForUninstall()
        await publishPolicyReconcileResult(result)
    }

    func cancelUninstallPreparation() async {
        guard let managementEngine else { return }
        let result = await managementEngine.cancelUninstallPreparation()
        await publishPolicyReconcileResult(result)
    }

    func shutdown() async {
        ioKitRefreshHandler = nil
        await managementEngine?.shutdown()
    }

    private func reconcilePolicy(on event: DaemonPolicyEvent) async {
        guard let managementEngine else { return }
        let result = await managementEngine.reconcilePolicy(on: event)
        await publishPolicyReconcileResult(result)
    }

    private func publishPolicyReconcileResult(_ result: DaemonPolicyReconcileResult) async {
        guard result.shouldPublishSnapshot else { return }
        if result.powerPathChanged {
            await publishSnapshotAfterPolicyReconcile()
        } else {
            await publishCurrentSnapshot()
        }
    }

    private func refreshHardwareState() async {
        do {
            await stateStore.updateHardwareState(try await hardware.readHardwareState())
        } catch {
            await stateStore.recordHardwareError(error)
        }
    }

    @discardableResult
    private func refreshIOKitSnapshot(
        reason: DaemonPowerSourceUpdateReason
    ) async -> Bool {
        guard
            let ioKitRefreshHandler,
            let update = await ioKitRefreshHandler(reason)
        else {
            return false
        }
        return await stateStore.updatePowerSource(update)
    }
}
