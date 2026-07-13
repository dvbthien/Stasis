import Foundation
import smc_power

final class ChargingDaemonCommandHandler: NSObject, ChargingDaemonProtocol, @unchecked Sendable {
    private let settingsStore: DaemonSettingsStore
    private let stateStore: DaemonStateStore
    private let runtime: DaemonRuntimeCoordinator
    private let hardware: any DaemonHardwareControlling
    private let capabilities: DaemonCapabilities
    private let daemonVersion: String
    private let clients: DaemonClientRegistry
    private let clientID: UUID

    init(
        settingsStore: DaemonSettingsStore,
        stateStore: DaemonStateStore,
        runtime: DaemonRuntimeCoordinator,
        hardware: any DaemonHardwareControlling,
        capabilities: DaemonCapabilities,
        daemonVersion: String,
        clients: DaemonClientRegistry,
        clientID: UUID = UUID()
    ) {
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.runtime = runtime
        self.hardware = hardware
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
            hardware: hardware,
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
        respond(reply: reply) { [stateStore, runtime] in
            try await stateStore.setChargeLimitOverride(enabled)
            let snapshot = await runtime.currentSnapshot(refreshHardware: false)
            await runtime.publishCurrentSnapshot()
            return snapshot
        }
    }

    func setForceDischarge(
        authData _: Data?,
        enabled: Bool,
        reply: @escaping @Sendable (Data?, String?) -> Void
    ) {
        respond(reply: reply) { [stateStore, runtime] in
            try await stateStore.setForceDischarge(enabled)
            let snapshot = await runtime.currentSnapshot(refreshHardware: false)
            await runtime.publishCurrentSnapshot()
            return snapshot
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

    func manageBatteryCharging(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        runCompatibilityCommand(reply: reply) { [hardware] in
            try await hardware.setChargingEnabled(enabled)
        }
    }

    func manageExternalPower(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        runCompatibilityCommand(reply: reply) { [hardware] in
            try await hardware.setAdapterEnabled(enabled)
        }
    }

    func manageMagsafeLED(
        target: UInt8,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        runCompatibilityCommand(reply: reply) { [hardware] in
            try await hardware.setMagSafeLED(rawValue: target)
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
            await runtime.publishCurrentSnapshot()
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

    private func runCompatibilityCommand(
        reply: @escaping @Sendable (Bool, String?) -> Void,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        Task { [runtime] in
            do {
                try await operation()
                await runtime.refreshAfterHardwareChange()
                reply(true, nil)
            } catch {
                reply(false, Self.errorMessage(for: error))
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
