import XCTest

final class ChargingDaemonCommandHandlerTests: XCTestCase {
    func testEachTypedGetterAndSetter() async throws {
        let handler = makeHandler()

        let management: ChargingManagementSettings = try await set(
            .init(isEnabled: true), using: handler.setChargingManagementSettings
        )
        XCTAssertTrue(management.isEnabled)
        let fetchedManagement: ChargingManagementSettings = try await get(
            using: handler.getChargingManagementSettings
        )
        XCTAssertEqual(fetchedManagement, management)

        let threshold: ChargingThresholdSettings = try await set(
            .init(chargeLimit: 75, sailingModeEnabled: true, sailingDelta: 5),
            using: handler.setChargingThresholdSettings
        )
        XCTAssertEqual(threshold.chargeLimit, 75)

        let discharge: AutomaticDischargeSettings = try await set(
            .init(isEnabled: false), using: handler.setAutomaticDischargeSettings
        )
        XCTAssertFalse(discharge.isEnabled)

        let sleep: SleepPreventionSettings = try await set(
            .init(isEnabled: true), using: handler.setSleepPreventionSettings
        )
        XCTAssertTrue(sleep.isEnabled)

        let heat: HeatProtectionSettings = try await set(
            .init(isEnabled: true, temperatureLimit: 42), using: handler.setHeatProtectionSettings
        )
        XCTAssertEqual(heat.temperatureLimit, 42)

        let led: MagSafeLEDSettings = try await set(
            .init(isEnabled: true, heatProtectionState: .blinkOrangeFast), using: handler.setMagSafeLEDSettings
        )
        XCTAssertEqual(led.heatProtectionState, .blinkOrangeFast)

        let percentage: BatteryPercentageSettings = try await set(
            .init(useHardwarePercentage: true), using: handler.setBatteryPercentageSettings
        )
        XCTAssertTrue(percentage.useHardwarePercentage)
    }

    func testMalformedPayloadIsRejectedAndStateIsPreserved() async throws {
        let handler = makeHandler()
        let error = await requestError { reply in
            handler.setChargingThresholdSettings(payload: Data("bad".utf8), reply: reply)
        }
        XCTAssertNotNil(error)
        let settings: ChargingThresholdSettings = try await get(using: handler.getChargingThresholdSettings)
        XCTAssertEqual(settings, .init())
    }

    func testInvalidGroupPayloadIsRejected() async throws {
        let handler = makeHandler()
        let invalid = ChargingThresholdSettings(chargeLimit: 55, sailingModeEnabled: true, sailingDelta: 10)
        let payload = try DaemonPayloadCodec.encode(invalid)
        let error = await requestError { reply in
            handler.setChargingThresholdSettings(payload: payload, reply: reply)
        }
        XCTAssertTrue(error?.contains("Invalid settings") == true)
    }

    private func makeHandler() -> ChargingDaemonCommandHandler {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let store = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())
        let state = DaemonStateStore(capabilities: capabilities, daemonVersion: "test")
        let clients = DaemonClientRegistry()
        let runtime = DaemonRuntimeCoordinator(
            settingsStore: store,
            stateStore: state,
            hardware: HandlerHardwareMock(),
            clients: clients
        )
        return ChargingDaemonCommandHandler(
            settingsStore: store,
            stateStore: state,
            runtime: runtime,
            capabilities: capabilities,
            daemonVersion: "test",
            executableHash: "test-hash",
            clients: clients
        )
    }

    private func set<Value: Codable & Sendable>(
        _ value: Value,
        using method: (Data, @escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async throws -> Value {
        let payload = try DaemonPayloadCodec.encode(value)
        return try await withCheckedThrowingContinuation { continuation in
            method(payload) { response, error in
                do {
                    guard let response else { throw NSError(domain: error ?? "XPC", code: 1) }
                    continuation.resume(returning: try DaemonPayloadCodec.decode(Value.self, from: response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func get<Value: Decodable & Sendable>(
        using method: (@escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            method { response, error in
                do {
                    guard let response else { throw NSError(domain: error ?? "XPC", code: 1) }
                    continuation.resume(returning: try DaemonPayloadCodec.decode(Value.self, from: response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestError(
        _ operation: (@escaping @Sendable (Data?, String?) -> Void) -> Void
    ) async -> String? {
        await withCheckedContinuation { continuation in
            operation { _, error in continuation.resume(returning: error) }
        }
    }
}

private actor HandlerHardwareMock: DaemonHardwareControlling {
    func setChargingEnabled(_ enabled: Bool) -> Bool { false }
    func setAdapterEnabled(_ enabled: Bool) -> Bool { false }
    func setMagSafeLED(rawValue: UInt8) -> Bool { false }
    func readHardwareState() -> DaemonHardwareState { .init() }
}
