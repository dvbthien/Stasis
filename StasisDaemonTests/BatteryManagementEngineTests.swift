import XCTest

final class BatteryManagementEngineTests: XCTestCase {
    func testEnabledManagementAppliesPolicyUsingStoredThreshold() async throws {
        let persistence = InMemoryChargingSettingsPersistence()
        let settings = ChargingSettingsStore(persistence: persistence)
        _ = await settings.setChargingManagementSettings(.init(isEnabled: true))
        _ = try await settings.setChargingThresholdSettings(.init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5))
        let state = DaemonStateStore(capabilities: .legacy, daemonVersion: "test")
        _ = await state.updatePowerSource(.init(
            battery: .init(displayedPercentage: 80, hardwarePercentage: 80),
            adapter: .init(physicallyConnected: true),
            reason: .initial
        ))
        let hardware = EngineHardwareMock()
        let engine = BatteryManagementEngine(
            capabilities: .legacy,
            settingsStore: settings,
            stateStore: state,
            hardware: hardware,
            sleepAssertion: EngineSleepMock(),
            retryDelay: .seconds(60)
        )
        await engine.start()

        _ = await engine.reconcilePolicy(on: .startup)

        let chargingEnabled = await hardware.lastChargingEnabled
        XCTAssertEqual(chargingEnabled, false)
        await engine.shutdown()
    }

    func testCapabilityGatingSkipsUnsupportedAdapterAndLEDWithoutChangingPreferences() async throws {
        let settings = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())
        _ = await settings.setChargingManagementSettings(.init(isEnabled: true))
        _ = await settings.setAutomaticDischargeSettings(.init(isEnabled: true))
        _ = await settings.setMagSafeLEDSettings(.init(isEnabled: true, heatProtectionState: .blinkOrangeSlow))
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: false,
            magSafeLEDKeyAvailable: false
        )
        let state = DaemonStateStore(capabilities: capabilities, daemonVersion: "test")
        _ = await state.updatePowerSource(.init(
            battery: .init(displayedPercentage: 85, hardwarePercentage: 85),
            adapter: .init(physicallyConnected: true),
            reason: .initial
        ))
        let hardware = EngineHardwareMock()
        let engine = BatteryManagementEngine(
            capabilities: capabilities,
            settingsStore: settings,
            stateStore: state,
            hardware: hardware,
            sleepAssertion: EngineSleepMock(),
            retryDelay: .seconds(60)
        )
        await engine.start()
        _ = await engine.reconcilePolicy(on: .startup)

        let adapterEnabled = await hardware.lastAdapterEnabled
        let ledState = await hardware.lastLED
        let discharge = await settings.automaticDischargeSettings()
        let led = await settings.magSafeLEDSettings()
        XCTAssertNil(adapterEnabled)
        XCTAssertNil(ledState)
        XCTAssertTrue(discharge.isEnabled)
        XCTAssertTrue(led.isEnabled)
        await engine.shutdown()
    }
}

private extension DaemonCapabilities {
    static let legacy = DaemonCapabilities(
        chargeControlMode: .legacy,
        adapterControl: true,
        magSafeLEDKeyAvailable: true
    )
}

private actor EngineHardwareMock: DaemonHardwareControlling {
    var lastChargingEnabled: Bool?
    var lastAdapterEnabled: Bool?
    var lastLED: UInt8?

    func setChargingEnabled(_ enabled: Bool) -> Bool { lastChargingEnabled = enabled; return true }
    func setAdapterEnabled(_ enabled: Bool) -> Bool { lastAdapterEnabled = enabled; return true }
    func setMagSafeLED(rawValue: UInt8) -> Bool { lastLED = rawValue; return true }
    func readHardwareState() -> DaemonHardwareState { .init() }
}

private actor EngineSleepMock: DaemonSleepAssertionControlling {
    func update(shouldPreventSleep _: Bool) {}
}
