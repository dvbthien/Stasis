import Foundation

final class ChargingDaemonCommandHandler: NSObject, ChargingDaemonProtocol, @unchecked Sendable {
    private let settingsStore: ChargingSettingsStore
    private let stateStore: DaemonStateStore
    private let runtime: DaemonRuntimeCoordinator
    private let capabilities: DaemonCapabilities
    private let daemonVersion: String
    private let executableHash: String?
    private let clients: DaemonClientRegistry

    init(
        settingsStore: ChargingSettingsStore,
        stateStore: DaemonStateStore,
        runtime: DaemonRuntimeCoordinator,
        capabilities: DaemonCapabilities,
        daemonVersion: String,
        executableHash: String?,
        clients: DaemonClientRegistry
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.runtime = runtime
        self.capabilities = capabilities
        self.daemonVersion = daemonVersion
        self.executableHash = executableHash
        self.clients = clients
    }

    func scoped(to _: UUID) -> ChargingDaemonCommandHandler {
        ChargingDaemonCommandHandler(
            settingsStore: settingsStore,
            stateStore: stateStore,
            runtime: runtime,
            capabilities: capabilities,
            daemonVersion: daemonVersion,
            executableHash: executableHash,
            clients: clients
        )
    }

    func connectionInvalidated() {}

    func checkHealth(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let status: DaemonRuntimeStatus = capabilities.chargingControl ? .ready : .unsupported
        sendEncodedResponse(reply: reply) { [capabilities, daemonVersion, executableHash] in
            DaemonHealth(
                status: status,
                daemonVersion: daemonVersion,
                chargeControlMode: capabilities.chargeControlMode,
                executableHash: executableHash
            )
        }
    }

    func getSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void) {
        sendEncodedResponse(reply: reply) { [runtime] in await runtime.currentSnapshot() }
    }

    func getAllSettings(reply: @escaping @Sendable (Data?, String?) -> Void) {
        sendEncodedResponse(reply: reply) { [settingsStore] in await settingsStore.allSettings() }
    }

    func setChargingManagementSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: ChargingManagementSettings.self, reply: reply) { store, value in
            await store.setChargingManagementSettings(value)
        }
    }

    func setChargingThresholdSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: ChargingThresholdSettings.self, reply: reply) { store, value in
            try await store.setChargingThresholdSettings(value)
        }
    }

    func setAutomaticDischargeSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: AutomaticDischargeSettings.self, reply: reply) { store, value in
            await store.setAutomaticDischargeSettings(value)
        }
    }

    func setSleepPreventionSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: SleepPreventionSettings.self, reply: reply) { store, value in
            await store.setSleepPreventionSettings(value)
        }
    }

    func setHeatProtectionSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: HeatProtectionSettings.self, reply: reply) { store, value in
            try await store.setHeatProtectionSettings(value)
        }
    }

    func setMagSafeLEDSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: MagSafeLEDSettings.self, reply: reply) { store, value in
            await store.setMagSafeLEDSettings(value)
        }
    }

    func setBatteryPercentageSettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        decodePersistAndReconcile(payload, as: BatteryPercentageSettings.self, reply: reply) { store, value in
            await store.setBatteryPercentageSettings(value)
        }
    }

    func setChargeLimitOverride(
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        sendEncodedResponse(reply: reply) { [runtime] in try await runtime.setChargeLimitOverride(enabled) }
    }

    func setForceDischarge(
        authData _: Data?,
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        sendEncodedResponse(reply: reply) { [runtime] in try await runtime.setForceDischarge(enabled) }
    }

    func prepareForUninstall(
        authData _: Data?,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        Task { [runtime] in
            do {
                try await runtime.prepareForUninstall()
                reply(true, nil)
            } catch {
                reply(false, Self.errorMessage(for: error))
            }
        }
    }

    func cancelUninstallPreparation(reply: @escaping @Sendable (Bool) -> Void) {
        Task { [runtime] in
            await runtime.cancelUninstallPreparation()
            reply(true)
        }
    }

    private func decodePersistAndReconcile<Value: Codable & Sendable>(
        _ payload: Data,
        as type: Value.Type,
        reply: @escaping @Sendable (Data?, String?) -> Void,
        setter: @escaping @Sendable (ChargingSettingsStore, Value) async throws -> Value
    ) {
        sendEncodedResponse(reply: reply) { [settingsStore, runtime] in
            let candidate = try DaemonPayloadCodec.decode(type, from: payload)
            let canonical = try await setter(settingsStore, candidate)
            await runtime.reconcilePolicyAfterSettingsChange()
            return canonical
        }
    }

    private func sendEncodedResponse<Value: Encodable & Sendable>(
        reply: @escaping @Sendable (Data?, String?) -> Void,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        Task {
            do {
                reply(try DaemonPayloadCodec.encode(await operation()), nil)
            } catch {
                reply(nil, Self.errorMessage(for: error))
            }
        }
    }

    private static func errorMessage(for error: Error) -> String {
        switch error {
        case let error as ChargingSettingsValidationError:
            "Invalid settings: \(error)"
        case let error as DecodingError:
            "Invalid payload: \(error.localizedDescription)"
        case let error as DaemonErrorPayload:
            error.message
        default:
            error.localizedDescription
        }
    }
}
