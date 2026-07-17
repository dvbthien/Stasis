import XCTest

/// Engine-level coverage for the macOS 27 firmware charge-control path:
/// the engine must drive `FirmwareChargeControlStrategy` through the same
/// public API as legacy mode, program only the firmware limit keys, and
/// never fall back to legacy charging or MagSafe control.
final class BatteryManagementEngineFirmwareTests: XCTestCase {
    func testFirmwareModeProgramsLimitWithSailingDeltaAndNeverTouchesLegacyControls() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )

        _ = await fixture.engine.reconcilePolicy(on: .startup)

        let calls = await fixture.hardware.calls
        XCTAssertEqual(calls, [.ensureLimit(lower: 75, upper: 80)])
        await fixture.engine.shutdown()
    }

    func testFirmwareModeWithoutSailingUsesOnePercentWindow() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: false, sailingDelta: 5)
        )

        _ = await fixture.engine.reconcilePolicy(on: .startup)

        let calls = await fixture.hardware.calls
        XCTAssertEqual(calls, [.ensureLimit(lower: 79, upper: 80)])
        await fixture.engine.shutdown()
    }

    func testChargeLimitOverrideDeactivatesFirmwareLimit() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )
        _ = await fixture.engine.reconcilePolicy(on: .startup)
        await fixture.hardware.reset()

        _ = try await fixture.engine.setChargeLimitOverride(true)

        let overrideCalls = await fixture.hardware.calls
        XCTAssertEqual(overrideCalls, [.ensureLimitDisabled])

        await fixture.hardware.reset()
        _ = try await fixture.engine.setChargeLimitOverride(false)

        let restoredCalls = await fixture.hardware.calls
        XCTAssertEqual(restoredCalls, [.ensureLimit(lower: 75, upper: 80)])
        await fixture.engine.shutdown()
    }

    func testForceDischargeDisablesLimitAndAdapterThenRestoresBoth() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )
        _ = await fixture.engine.reconcilePolicy(on: .startup)
        await fixture.hardware.reset()

        _ = try await fixture.engine.setForceDischarge(true)

        let dischargeCalls = await fixture.hardware.calls
        XCTAssertEqual(dischargeCalls, [.ensureLimitDisabled, .adapter(false)])

        await fixture.hardware.reset()
        _ = try await fixture.engine.setForceDischarge(false)

        let restoredCalls = await fixture.hardware.calls
        XCTAssertEqual(
            restoredCalls,
            [.adapter(true), .ensureLimit(lower: 75, upper: 80)]
        )
        await fixture.engine.shutdown()
    }

    func testAdapterDisconnectDuringForceDischargeRestoresAdapter() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )
        _ = await fixture.engine.reconcilePolicy(on: .startup)
        _ = try await fixture.engine.setForceDischarge(true)
        await fixture.hardware.reset()

        _ = await fixture.state.updatePowerSource(.init(
            battery: .init(displayedPercentage: 85, hardwarePercentage: 85),
            adapter: .init(physicallyConnected: false),
            reason: .interestNotification
        ))
        _ = await fixture.engine.reconcilePolicy(on: .powerSource)

        let calls = await fixture.hardware.calls
        XCTAssertEqual(calls, [.ensureLimitDisabled, .adapter(true)])

        let context = await fixture.state.managementContext()
        XCTAssertFalse(context.forceDischargeActive)
        await fixture.engine.shutdown()
    }

    func testShutdownRestoresFirmwareDefaults() async throws {
        let fixture = await makeFixture(
            threshold: .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )
        _ = await fixture.engine.reconcilePolicy(on: .startup)
        await fixture.hardware.reset()

        await fixture.engine.shutdown()

        let calls = await fixture.hardware.calls
        XCTAssertEqual(calls, [.ensureLimitDisabled, .adapter(true)])
    }

    // MARK: - Fixture

    private struct Fixture {
        let engine: BatteryManagementEngine
        let hardware: FirmwareHardwareMock
        let state: DaemonStateStore
    }

    private func makeFixture(
        threshold: ChargingThresholdSettings
    ) async -> Fixture {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .firmware,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let settings = ChargingSettingsStore(
            persistence: InMemoryChargingSettingsPersistence()
        )
        _ = await settings.setChargingManagementSettings(.init(isEnabled: true))
        _ = try? await settings.setChargingThresholdSettings(threshold)

        let state = DaemonStateStore(capabilities: capabilities, daemonVersion: "test")
        _ = await state.updatePowerSource(.init(
            battery: .init(displayedPercentage: 85, hardwarePercentage: 85),
            adapter: .init(physicallyConnected: true),
            reason: .initial
        ))

        let hardware = FirmwareHardwareMock()
        let engine = BatteryManagementEngine(
            capabilities: capabilities,
            settingsStore: settings,
            stateStore: state,
            hardware: hardware,
            sleepAssertion: FirmwareSleepMock(),
            retryDelay: .seconds(60)
        )
        await engine.start()
        return Fixture(engine: engine, hardware: hardware, state: state)
    }
}

private actor FirmwareHardwareMock: DaemonHardwareControlling {
    enum Call: Equatable {
        case charging(Bool)
        case adapter(Bool)
        case led(UInt8)
        case ensureLimit(lower: Int, upper: Int)
        case ensureLimitDisabled
    }

    private(set) var calls: [Call] = []
    private var firmwareLimitActive = false

    func reset() { calls = [] }

    func setChargingEnabled(_ enabled: Bool) -> Bool {
        calls.append(.charging(enabled))
        return true
    }

    func setAdapterEnabled(_ enabled: Bool) -> Bool {
        calls.append(.adapter(enabled))
        return true
    }

    func setMagSafeLED(rawValue: UInt8) -> Bool {
        calls.append(.led(rawValue))
        return true
    }

    func ensureFirmwareChargeLimit(lower: Int, upper: Int) -> Bool {
        calls.append(.ensureLimit(lower: lower, upper: upper))
        firmwareLimitActive = true
        return true
    }

    func ensureFirmwareChargeLimitDisabled() -> Bool {
        calls.append(.ensureLimitDisabled)
        let changed = firmwareLimitActive
        firmwareLimitActive = false
        return changed
    }

    func readHardwareState() -> DaemonHardwareState { .init() }
}

private actor FirmwareSleepMock: DaemonSleepAssertionControlling {
    func update(shouldPreventSleep _: Bool) {}
}
