import XCTest

final class ChargeLimitPolicyTests: XCTestCase {
    @MainActor
    func testPlainSettingsSnapshotPreservesEveryPolicyInput() {
        let settings = DaemonSettings(
            managementEnabled: true,
            chargeLimit: 77,
            useHardwarePercentage: true,
            sailingModeEnabled: false,
            sailingDelta: 3,
            automaticDischarge: false,
            preventSleepUntilLimit: true,
            heatProtectionEnabled: false,
            heatProtectionLimit: 42,
            manageMagSafeLED: false,
            heatProtectionLEDStateRawValue: 7
        )

        let snapshot = ChargingSettingsSnapshot(
            settings: settings,
            chargeLimitOverrideActive: false
        )

        XCTAssertEqual(snapshot.chargeLimit, 77)
        XCTAssertTrue(snapshot.useHardwarePercentage)
        XCTAssertFalse(snapshot.sailingModeEnabled)
        XCTAssertEqual(snapshot.sailingModeLimit, 3)
        XCTAssertFalse(snapshot.automaticDischarge)
        XCTAssertFalse(snapshot.manageMagSafeLED)
        XCTAssertFalse(snapshot.heatProtectionEnabled)
        XCTAssertEqual(snapshot.heatProtectionLimit, 42)
        XCTAssertEqual(snapshot.heatProtectionMagSafeLEDState.rawValue, 7)
        XCTAssertTrue(snapshot.disableSleepUntilChargeLimit)

        let overrideSnapshot = ChargingSettingsSnapshot(
            settings: settings,
            chargeLimitOverrideActive: true
        )
        XCTAssertEqual(overrideSnapshot.chargeLimit, 100)
    }

    @MainActor
    func testBelowLimitChargesNormally() {
        var hasReachedChargeLimit = false

        let decision = ChargeLimitPolicy.evaluate(
            controlState: controlState(displayedPercentage: 60),
            settings: policySettings(sailingModeEnabled: false),
            stateWasCleared: false,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        XCTAssertEqual(decision.desiredCharging, true)
        XCTAssertEqual(decision.desiredAdapter, true)
        XCTAssertEqual(decision.desiredLED?.rawValue, 4)
        XCTAssertFalse(hasReachedChargeLimit)
    }

    @MainActor
    func testAtLimitStopsChargingWithoutDisablingAdapter() {
        var hasReachedChargeLimit = false

        let decision = ChargeLimitPolicy.evaluate(
            controlState: controlState(displayedPercentage: 80),
            settings: policySettings(),
            stateWasCleared: false,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredAdapter, true)
        XCTAssertEqual(decision.desiredLED?.rawValue, 3)
        XCTAssertTrue(hasReachedChargeLimit)
    }

    @MainActor
    func testAboveLimitAutomaticallyDischargesWhenEnabled() {
        var hasReachedChargeLimit = false

        let decision = ChargeLimitPolicy.evaluate(
            controlState: controlState(displayedPercentage: 81),
            settings: policySettings(automaticDischarge: true),
            stateWasCleared: false,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredAdapter, false)
        XCTAssertTrue(hasReachedChargeLimit)
    }

    @MainActor
    func testSailingModePrimesAndReleasesHysteresis() {
        var hasReachedChargeLimit = false
        let settings = policySettings(sailingModeEnabled: true, sailingDelta: 5)

        let holdingDecision = ChargeLimitPolicy.evaluate(
            controlState: controlState(displayedPercentage: 78),
            settings: settings,
            stateWasCleared: true,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        XCTAssertEqual(holdingDecision.desiredCharging, false)
        XCTAssertTrue(hasReachedChargeLimit)

        let chargingDecision = ChargeLimitPolicy.evaluate(
            controlState: controlState(displayedPercentage: 74),
            settings: settings,
            stateWasCleared: false,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        XCTAssertEqual(chargingDecision.desiredCharging, true)
        XCTAssertEqual(chargingDecision.desiredAdapter, true)
        XCTAssertFalse(hasReachedChargeLimit)
    }

    @MainActor
    func testHeatProtectionOverridesChargeDecision() {
        var decision = ChargingDecision(
            desiredCharging: true,
            desiredAdapter: true,
            desiredLED: nil,
            reason: nil
        )

        HeatProtectionPolicy.apply(
            to: &decision,
            controlState: controlState(displayedPercentage: 50, temperature: 41),
            settings: policySettings(heatProtectionEnabled: true, heatProtectionLimit: 40)
        )

        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredAdapter, true)
        XCTAssertEqual(decision.desiredLED?.rawValue, 6)
        XCTAssertEqual(decision.reason, "Battery temperature exceeds 40°C")
    }

    @MainActor
    func testForceDischargeOverridesChargingAndAdapter() {
        var decision = ChargingDecision(
            desiredCharging: true,
            desiredAdapter: true,
            desiredLED: nil,
            reason: nil
        )

        ForceDischargePolicy.apply(to: &decision, isActive: true)

        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredAdapter, false)
    }

    @MainActor
    func testHardwarePercentageSelectionChangesDecisionInput() {
        let state = controlState(
            displayedPercentage: 40,
            hardwarePercentage: 81
        )
        var displayHysteresis = false
        var hardwareHysteresis = false

        let displayDecision = ChargeLimitPolicy.evaluate(
            controlState: state,
            settings: policySettings(useHardwarePercentage: false, sailingModeEnabled: false),
            stateWasCleared: false,
            hasReachedChargeLimit: &displayHysteresis
        )
        let hardwareDecision = ChargeLimitPolicy.evaluate(
            controlState: state,
            settings: policySettings(useHardwarePercentage: true, sailingModeEnabled: false),
            stateWasCleared: false,
            hasReachedChargeLimit: &hardwareHysteresis
        )

        XCTAssertEqual(displayDecision.desiredCharging, true)
        XCTAssertEqual(hardwareDecision.desiredCharging, false)
        XCTAssertEqual(hardwareDecision.desiredAdapter, false)
    }

    @MainActor
    private func controlState(
        displayedPercentage: Int,
        hardwarePercentage: Int? = nil,
        temperature: Double = 30
    ) -> BatteryControlState {
        BatteryControlState(
            batteryPercentage: displayedPercentage,
            hardwareBatteryPercentage: hardwarePercentage ?? displayedPercentage,
            adapterConnected: true,
            batteryTemperature: temperature
        )
    }

    @MainActor
    private func policySettings(
        useHardwarePercentage: Bool = false,
        sailingModeEnabled: Bool = true,
        sailingDelta: Int = 5,
        automaticDischarge: Bool = true,
        heatProtectionEnabled: Bool = true,
        heatProtectionLimit: Int = 40
    ) -> ChargingSettingsSnapshot {
        let settings = DaemonSettings(
            managementEnabled: true,
            chargeLimit: 80,
            useHardwarePercentage: useHardwarePercentage,
            sailingModeEnabled: sailingModeEnabled,
            sailingDelta: sailingDelta,
            automaticDischarge: automaticDischarge,
            preventSleepUntilLimit: false,
            heatProtectionEnabled: heatProtectionEnabled,
            heatProtectionLimit: heatProtectionLimit,
            manageMagSafeLED: true,
            heatProtectionLEDStateRawValue: 6
        )
        return ChargingSettingsSnapshot(
            settings: settings,
            chargeLimitOverrideActive: false
        )
    }
}
