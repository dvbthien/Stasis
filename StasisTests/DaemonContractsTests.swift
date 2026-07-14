import XCTest

@testable import stasis

@MainActor
final class DaemonContractsTests: XCTestCase {
    func testEverySettingsModelRoundTripsThroughPayloadCodec() throws {
        try assertRoundTrip(ChargingManagementSettings(isEnabled: true))
        try assertRoundTrip(ChargingThresholdSettings(chargeLimit: 75, sailingModeEnabled: true, sailingDelta: 5))
        try assertRoundTrip(AutomaticDischargeSettings(isEnabled: false))
        try assertRoundTrip(SleepPreventionSettings(isEnabled: true))
        try assertRoundTrip(HeatProtectionSettings(isEnabled: true, temperatureLimit: 42))
        try assertRoundTrip(MagSafeLEDSettings(isEnabled: true, heatProtectionState: .blinkOrangeFast))
        try assertRoundTrip(BatteryPercentageSettings(useHardwarePercentage: true))
    }

    func testCapabilitiesAreDerivedFromChargeControlMode() {
        let legacy = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let legacyDischarge = legacy.automaticDischargeControl
        let legacySleep = legacy.sleepHooks
        let legacyLED = legacy.magSafeLEDControl
        XCTAssertTrue(legacyDischarge)
        XCTAssertTrue(legacySleep)
        XCTAssertTrue(legacyLED)

        let firmware = DaemonCapabilities(
            chargeControlMode: .firmware,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let firmwareCharging = firmware.chargingControl
        let firmwareDischarge = firmware.automaticDischargeControl
        let firmwareHeat = firmware.heatProtectionControl
        XCTAssertTrue(firmwareCharging)
        XCTAssertFalse(firmwareDischarge)
        XCTAssertFalse(firmwareHeat)
    }

    private func assertRoundTrip<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let payload = try DaemonPayloadCodec.encode(value)
        XCTAssertEqual(
            try DaemonPayloadCodec.decode(Value.self, from: payload),
            value,
            file: file,
            line: line
        )
    }
}
