import XCTest

final class ChargeLimitPolicyTests: XCTestCase {
    func testPolicyInputUsesHardwareOrCalibratedPercentage() {
        let state = BatteryControlState(
            batteryPercentage: 79,
            hardwareBatteryPercentage: 82,
            adapterConnected: true,
            batteryTemperature: 30
        )
        XCTAssertEqual(input(useHardwarePercentage: false).batteryPercentage(for: state), 79)
        XCTAssertEqual(input(useHardwarePercentage: true).batteryPercentage(for: state), 82)
    }

    func testAtLimitStopsCharging() {
        var reached = false
        let decision = ChargeLimitPolicy.evaluate(
            controlState: state(percentage: 80),
            settings: input(),
            stateWasCleared: false,
            hasReachedChargeLimit: &reached
        )
        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredAdapter, true)
        XCTAssertTrue(reached)
    }

    func testAutomaticDischargeControlsAdapterAboveLimit() {
        var reached = false
        let decision = ChargeLimitPolicy.evaluate(
            controlState: state(percentage: 85),
            settings: input(automaticDischarge: true),
            stateWasCleared: false,
            hasReachedChargeLimit: &reached
        )
        XCTAssertEqual(decision.desiredAdapter, false)
    }

    func testSailingModeWaitsWithinHysteresisAfterLimitReached() {
        var reached = true
        let decision = ChargeLimitPolicy.evaluate(
            controlState: state(percentage: 77),
            settings: input(),
            stateWasCleared: false,
            hasReachedChargeLimit: &reached
        )
        XCTAssertEqual(decision.desiredCharging, false)
    }

    func testSailingModeResumesBelowThreshold() {
        var reached = true
        let decision = ChargeLimitPolicy.evaluate(
            controlState: state(percentage: 74),
            settings: input(),
            stateWasCleared: false,
            hasReachedChargeLimit: &reached
        )
        XCTAssertEqual(decision.desiredCharging, true)
        XCTAssertFalse(reached)
    }

    func testHeatProtectionOverridesChargingDecision() {
        var decision = ChargingDecision(
            desiredCharging: true,
            desiredAdapter: true,
            desiredLED: nil,
            reason: nil
        )
        HeatProtectionPolicy.apply(
            to: &decision,
            controlState: state(percentage: 60, temperature: 41),
            settings: input()
        )
        XCTAssertEqual(decision.desiredCharging, false)
        XCTAssertEqual(decision.desiredLED, .blinkOrangeSlow)
    }

    private func input(
        useHardwarePercentage: Bool = false,
        automaticDischarge: Bool = true
    ) -> ChargingPolicyInput {
        ChargingPolicyInput(
            threshold: .init(),
            automaticDischarge: .init(isEnabled: automaticDischarge),
            sleepPrevention: .init(),
            heatProtection: .init(),
            magSafeLED: .init(),
            batteryPercentage: .init(useHardwarePercentage: useHardwarePercentage),
            chargeLimitOverrideActive: false
        )
    }

    private func state(percentage: Int, temperature: Double = 30) -> BatteryControlState {
        .init(
            batteryPercentage: percentage,
            hardwareBatteryPercentage: percentage,
            adapterConnected: true,
            batteryTemperature: temperature
        )
    }
}
