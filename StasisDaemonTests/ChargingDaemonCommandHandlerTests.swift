import Foundation
import XCTest

final class ChargingDaemonCommandHandlerTests: XCTestCase {
    func testCommandSurfacePersistsCanonicalSettingsAcrossReconnect() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let first = try await makeHandler(persistence: persistence)
        let legacySettings = settings(chargeLimit: 75)
        let importPayload = try DaemonPayloadCodec.encode(legacySettings)

        let imported: DaemonSettingsState = try await requestPayload { reply in
            first.handler.importLegacySettings(payload: importPayload, reply: reply)
        }

        let reconnected = try await makeHandler(persistence: persistence)
        let fetched: DaemonSettingsState = try await requestPayload { reply in
            reconnected.handler.getSettings(reply: reply)
        }

        XCTAssertEqual(fetched, imported)
        XCTAssertEqual(fetched.settings.chargeLimit, 75)
        XCTAssertFalse(fetched.needsLegacyImport)
    }

    func testInvalidCommandPayloadDoesNotChangeSettings() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let fixture = try await makeHandler(persistence: persistence)
        let before: DaemonSettingsState = try await requestPayload { reply in
            fixture.handler.getSettings(reply: reply)
        }

        let response = await requestRaw { reply in
            fixture.handler.setSettings(authData: nil, payload: Data([0xFF]), reply: reply)
        }
        let after: DaemonSettingsState = try await requestPayload { reply in
            fixture.handler.getSettings(reply: reply)
        }

        XCTAssertNil(response.data)
        XCTAssertNotNil(response.errorMessage)
        XCTAssertEqual(after, before)
    }

    func testTemporaryCommandsReturnUpdatedSnapshotsWithoutPersistence() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let fixture = try await makeHandler(persistence: persistence)
        let payload = try DaemonPayloadCodec.encode(settings(chargeLimit: 75))
        let _: DaemonSettingsState = try await requestPayload { reply in
            fixture.handler.setSettings(authData: nil, payload: payload, reply: reply)
        }
        await fixture.runtime.handlePowerSourceUpdate(
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 60),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .initial
            )
        )

        let overrideSnapshot: DaemonSnapshot = try await requestPayload { reply in
            fixture.handler.setChargeLimitOverride(enabled: true, reply: reply)
        }
        let forceSnapshot: DaemonSnapshot = try await requestPayload { reply in
            fixture.handler.setForceDischarge(authData: nil, enabled: true, reply: reply)
        }

        XCTAssertTrue(overrideSnapshot.policy.chargeLimitOverrideActive)
        XCTAssertFalse(forceSnapshot.policy.chargeLimitOverrideActive)
        XCTAssertTrue(forceSnapshot.policy.forceDischargeActive)

        let relaunched = try await makeHandler(persistence: persistence)
        let relaunchedSnapshot: DaemonSnapshot = try await requestPayload { reply in
            relaunched.handler.getSnapshot(reply: reply)
        }
        XCTAssertFalse(relaunchedSnapshot.policy.chargeLimitOverrideActive)
        XCTAssertFalse(relaunchedSnapshot.policy.forceDischargeActive)
    }

    func testHealthReportsChargeControlMode() async throws {
        let fixture = try await makeHandler(
            persistence: InMemoryDaemonSettingsPersistence()
        )

        let health: DaemonHealth = try await requestPayload { reply in
            fixture.handler.checkHealth(reply: reply)
        }

        XCTAssertEqual(health.status, .ready)
        XCTAssertEqual(health.chargeControlMode, .legacy)
    }

    func testConnectionInvalidationDoesNotResetHardware() async throws {
        let fixture = try await makeHandler(
            persistence: InMemoryDaemonSettingsPersistence()
        )

        fixture.handler.connectionInvalidated()
        try await Task.sleep(for: .milliseconds(20))

        let resetCount = await fixture.hardware.resetCount()
        let hardwareWriteCount = await fixture.hardware.writeCount()
        XCTAssertEqual(resetCount, 0)
        XCTAssertEqual(hardwareWriteCount, 0)
    }

    private func makeHandler(
        persistence: InMemoryDaemonSettingsPersistence
    ) async throws -> (
        handler: ChargingDaemonCommandHandler,
        runtime: DaemonRuntimeCoordinator,
        hardware: MockDaemonHardwareController
    ) {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let hardware = MockDaemonHardwareController()
        let settingsStore = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: capabilities
        )
        let stateStore = DaemonStateStore(
            capabilities: capabilities,
            daemonVersion: "test"
        )
        let clients = DaemonClientRegistry()
        let runtime = DaemonRuntimeCoordinator(
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            clients: clients
        )
        let engine = BatteryManagementEngine(
            capabilities: capabilities,
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            runtime: runtime
        )
        await runtime.installManagementEngine(engine)
        let handler = ChargingDaemonCommandHandler(
            settingsStore: settingsStore,
            stateStore: stateStore,
            runtime: runtime,
            hardware: hardware,
            capabilities: capabilities,
            daemonVersion: "test",
            clients: clients
        )
        return (handler, runtime, hardware)
    }

    private func settings(chargeLimit: Int) -> DaemonSettings {
        DaemonSettings(
            managementEnabled: true,
            chargeLimit: chargeLimit,
            sailingModeEnabled: true,
            sailingDelta: 5,
            automaticDischarge: true,
            heatProtectionEnabled: true,
            heatProtectionLimit: 40,
            manageMagSafeLED: true,
            heatProtectionLEDStateRawValue: 6
        )
    }

    private func requestPayload<Value: Decodable & Sendable>(
        _ operation: (@escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async throws -> Value {
        let response = await requestRaw(operation)
        if let errorMessage = response.errorMessage {
            throw TestCommandError.failed(errorMessage)
        }
        guard let data = response.data else { throw TestCommandError.missingPayload }
        return try DaemonPayloadCodec.decode(Value.self, from: data)
    }

    private func requestRaw(
        _ operation: (@escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async -> (data: Data?, errorMessage: String?) {
        await withCheckedContinuation { continuation in
            operation { data, errorMessage in
                continuation.resume(returning: (data, errorMessage))
            }
        }
    }
}

private enum TestCommandError: Error {
    case failed(String)
    case missingPayload
}

private actor MockDaemonHardwareController: DaemonHardwareControlling {
    private var resets = 0
    private var writes = 0
    func setChargingEnabled(_ enabled: Bool) async throws -> Bool {
        writes += 1
        return true
    }
    func setAdapterEnabled(_ enabled: Bool) async throws -> Bool {
        writes += 1
        return true
    }
    func setMagSafeLED(rawValue: UInt8) async throws -> Bool {
        writes += 1
        return true
    }

    func readHardwareState() async throws -> DaemonHardwareState {
        DaemonHardwareState(
            chargingInhibited: false,
            forceDischarging: false,
            magSafeLEDStateRawValue: 3
        )
    }

    func readTelemetry() async -> DaemonTelemetryReading {
        DaemonTelemetryReading()
    }

    func resetToDefaults() async {
        resets += 1
    }

    func resetCount() -> Int {
        resets
    }

    func writeCount() -> Int {
        writes
    }
}
