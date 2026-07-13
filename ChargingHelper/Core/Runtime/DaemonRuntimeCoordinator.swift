import Foundation

actor DaemonRuntimeCoordinator {
    typealias IOKitRefreshHandler = @Sendable (
        DaemonPowerSourceUpdateReason
    ) async -> DaemonPowerSourceUpdate?

    private let settingsStore: DaemonSettingsStore
    private let stateStore: DaemonStateStore
    private let hardware: any DaemonHardwareControlling
    private let clients: DaemonClientRegistry
    private let telemetryInterval: Duration
    private let delayedTelemetryRefreshDelay: Duration

    private var telemetryClients: Set<UUID> = []
    private var telemetryTask: Task<Void, Never>?
    private var delayedTelemetryTask: Task<Void, Never>?
    private var managementEngine: BatteryManagementEngine?
    private var ioKitRefreshHandler: IOKitRefreshHandler?

    init(
        settingsStore: DaemonSettingsStore,
        stateStore: DaemonStateStore,
        hardware: any DaemonHardwareControlling,
        clients: DaemonClientRegistry,
        telemetryInterval: Duration = .seconds(1),
        delayedTelemetryRefreshDelay: Duration = .seconds(3)
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.hardware = hardware
        self.clients = clients
        self.telemetryInterval = telemetryInterval
        self.delayedTelemetryRefreshDelay = delayedTelemetryRefreshDelay
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
            await refreshTelemetryAndPublish()
        } else {
            await publishCurrentSnapshot()
        }

        if update.reason == .interestNotification {
            scheduleDelayedTelemetryRefresh()
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
        let settingsState = await settingsStore.state()
        return await stateStore.snapshot(settingsState: settingsState)
    }

    func publishCurrentSnapshot(refreshHardware: Bool = false) async {
        let snapshot = await currentSnapshot(refreshHardware: refreshHardware)
        guard let payload = try? DaemonPayloadCodec.encode(snapshot) else { return }
        clients.publishSnapshot(payload)
    }

    func reconcilePolicyAfterHardwareCommand() async {
        _ = await refreshIOKitSnapshot(reason: .hardwareRefresh)
        await refreshTelemetryAndPublish(refreshHardware: true)
        scheduleDelayedTelemetryRefresh()
        await reconcilePolicy(on: .hardwareCommand)
    }

    /// Refreshes measurements after policy reconciliation has already applied
    /// hardware state. This deliberately does not enqueue another policy event.
    private func refreshTelemetryAfterPolicyReconcile() async {
        _ = await refreshIOKitSnapshot(reason: .hardwareRefresh)
        await refreshTelemetryAndPublish()
        scheduleDelayedTelemetryRefresh()
    }

    /// Samples telemetry and publishes one complete snapshot. IOKit-driven,
    /// client-demand, and post-hardware refreshes use this same path.
    func refreshTelemetryAndPublish(refreshHardware: Bool = false) async {
        await sampleTelemetry()
        await publishCurrentSnapshot(refreshHardware: refreshHardware)
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

    func setTelemetryActive(_ active: Bool, for clientID: UUID) async {
        if active {
            telemetryClients.insert(clientID)
            guard telemetryTask == nil else { return }
            await refreshTelemetryAndPublish()
            guard !telemetryClients.isEmpty else { return }
            startTelemetryLoop()
        } else {
            telemetryClients.remove(clientID)
            stopTelemetryLoopIfUnused()
        }
    }

    func clientDisconnected(_ clientID: UUID) {
        telemetryClients.remove(clientID)
        stopTelemetryLoopIfUnused()
    }

    func isTelemetryActive() -> Bool {
        telemetryTask != nil
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
        telemetryTask?.cancel()
        telemetryTask = nil
        delayedTelemetryTask?.cancel()
        delayedTelemetryTask = nil
        telemetryClients.removeAll()
        ioKitRefreshHandler = nil
        await managementEngine?.shutdown()
    }

    private func startTelemetryLoop() {
        telemetryTask = Task { [weak self, telemetryInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: telemetryInterval)
                guard !Task.isCancelled, let self else { return }
                await self.refreshTelemetryAndPublish()
            }
        }
    }

    private func scheduleDelayedTelemetryRefresh() {
        delayedTelemetryTask?.cancel()
        delayedTelemetryTask = Task { [weak self, delayedTelemetryRefreshDelay] in
            try? await Task.sleep(for: delayedTelemetryRefreshDelay)
            guard !Task.isCancelled, let self else { return }
            await self.finishDelayedTelemetryRefresh()
        }
    }

    private func finishDelayedTelemetryRefresh() async {
        delayedTelemetryTask = nil
        let powerSourceChanged = await refreshIOKitSnapshot(reason: .hardwareRefresh)
        await refreshTelemetryAndPublish()
        if powerSourceChanged {
            await reconcilePolicy(on: .powerSource)
        }
    }

    private func reconcilePolicy(on event: DaemonPolicyEvent) async {
        guard let managementEngine else { return }
        let result = await managementEngine.reconcilePolicy(on: event)
        await publishPolicyReconcileResult(result)
    }

    private func publishPolicyReconcileResult(_ result: DaemonPolicyReconcileResult) async {
        guard result.shouldPublishSnapshot else { return }
        if result.powerPathChanged {
            await refreshTelemetryAfterPolicyReconcile()
        } else {
            await publishCurrentSnapshot()
        }
    }

    private func stopTelemetryLoopIfUnused() {
        guard telemetryClients.isEmpty else { return }
        telemetryTask?.cancel()
        telemetryTask = nil
    }

    private func sampleTelemetry() async {
        let reading = await hardware.readTelemetry()
        _ = await stateStore.updateTelemetry(reading)
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
