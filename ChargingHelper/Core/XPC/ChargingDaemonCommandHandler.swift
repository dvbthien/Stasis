import Foundation

final class ChargingDaemonCommandHandler: NSObject, ChargingDaemonProtocol, @unchecked Sendable {
    private let settingsStore: DaemonSettingsStore
    private let stateStore: DaemonStateStore
    private let runtime: DaemonRuntimeCoordinator
    private let capabilities: DaemonCapabilities
    private let daemonVersion: String
    private let clients: DaemonClientRegistry
    private let clientID: UUID

    init(
        settingsStore: DaemonSettingsStore,
        stateStore: DaemonStateStore,
        runtime: DaemonRuntimeCoordinator,
        capabilities: DaemonCapabilities,
        daemonVersion: String,
        clients: DaemonClientRegistry,
        clientID: UUID = UUID()
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.runtime = runtime
        self.capabilities = capabilities
        self.daemonVersion = daemonVersion
        self.clients = clients
        self.clientID = clientID
    }

    func scoped(to clientID: UUID) -> ChargingDaemonCommandHandler {
        ChargingDaemonCommandHandler(
            settingsStore: settingsStore,
            stateStore: stateStore,
            runtime: runtime,
            capabilities: capabilities,
            daemonVersion: daemonVersion,
            clients: clients,
            clientID: clientID
        )
    }

    func connectionInvalidated() {
        Task { [runtime, clientID] in
            await runtime.clientDisconnected(clientID)
        }
    }

    func checkHealth(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let status: DaemonRuntimeStatus = capabilities.chargingControl ? .ready : .unsupported
        respond(reply: reply) { [capabilities, daemonVersion] in
            DaemonHealth(
                status: status,
                daemonVersion: daemonVersion,
                chargeControlMode: capabilities.chargeControlMode
            )
        }
    }

    func getSnapshot(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply: reply) { [runtime] in
            await runtime.currentSnapshot()
        }
    }

    func getSettings(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply: reply) { [settingsStore] in
            await settingsStore.state()
        }
    }

    func setSettings(
        authData _: Data?,
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        mutateSettings(payload: payload, importLegacy: false, reply: reply)
    }

    func importLegacySettings(
        payload: Data,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        mutateSettings(payload: payload, importLegacy: true, reply: reply)
    }

    func setChargeLimitOverride(
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        respond(reply: reply) { [runtime] in
            try await runtime.setChargeLimitOverride(enabled)
        }
    }

    func setForceDischarge(
        authData _: Data?,
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        respond(reply: reply) { [runtime] in
            try await runtime.setForceDischarge(enabled)
        }
    }

    func setTelemetryActive(
        _ active: Bool,
        reply: @escaping @Sendable (Bool) -> Void
    ) {
        Task { [runtime, clientID] in
            await runtime.setTelemetryActive(active, for: clientID)
            reply(true)
        }
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

    func cancelUninstallPreparation(
        reply: @escaping @Sendable (Bool) -> Void
    ) {
        Task { [runtime] in
            await runtime.cancelUninstallPreparation()
            reply(true)
        }
    }

    private func mutateSettings(
        payload: Data,
        importLegacy: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        respond(reply: reply) { [settingsStore, runtime, clients] in
            let settings = try DaemonPayloadCodec.decode(DaemonSettings.self, from: payload)
            let settingsState =
                if importLegacy {
                    try await settingsStore.importLegacySettings(settings)
                } else {
                    try await settingsStore.setSettings(settings)
                }

            let settingsPayload = try DaemonPayloadCodec.encode(settingsState)
            clients.publishSettings(settingsPayload)
            await runtime.reconcilePolicyAfterSettingsChange()
            return settingsState
        }
    }

    private func respond<Value: Encodable & Sendable>(
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
        case let error as DaemonSettingsValidationError:
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
