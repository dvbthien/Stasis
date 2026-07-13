import XCTest
@testable import stasis
import smc_power

final class DaemonContractsTests: XCTestCase {
    @MainActor
    func testWireChargeControlModeMapsFromSMCMode() {
        XCTAssertEqual(ChargeControlMode(smcMode: .unsupported), .unsupported)
        XCTAssertEqual(ChargeControlMode(smcMode: .legacy), .legacy)
        XCTAssertEqual(ChargeControlMode(smcMode: .firmware), .firmware)
    }

    @MainActor
    func testSettingsRoundTripPreservesEveryField() throws {
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

        let data = try DaemonPayloadCodec.encode(settings)
        let decoded = try DaemonPayloadCodec.decode(DaemonSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.schemaVersion, DaemonSettings.currentSchemaVersion)
    }

    @MainActor
    func testSnapshotRoundTripPreservesNestedState() throws {
        let snapshot = DaemonSnapshot(
            capabilities: DaemonCapabilities(
                chargeControlMode: .firmware,
                adapterControl: true,
                magSafeLEDKeyAvailable: true
            ),
            battery: DaemonBatterySnapshot(
                displayedPercentage: 79,
                hardwarePercentage: 78,
                isCharging: false,
                timeRemaining: 120,
                voltage: 12.4,
                current: -1.2,
                power: -14.88,
                temperature: 36.5,
                health: 91,
                cycleCount: 245
            ),
            adapter: DaemonAdapterSnapshot(
                physicallyConnected: true,
                powerEnabled: true,
                voltage: 20,
                current: 2.5,
                power: 50
            ),
            hardware: DaemonHardwareState(
                chargingInhibited: nil,
                forceDischarging: false,
                magSafeLEDStateRawValue: nil,
                firmwareChargeLimit: DaemonFirmwareChargeLimitState(
                    active: true,
                    lower: 75,
                    upper: 80
                )
            ),
            policy: DaemonPolicyState(
                managementEnabled: true,
                chargeLimitOverrideActive: false,
                forceDischargeActive: false,
                desiredCharging: nil,
                desiredAdapter: nil,
                desiredLEDStateRawValue: nil,
                reason: "Firmware owns charge enforcement"
            ),
            runtime: DaemonRuntimeState(
                status: .ready,
                daemonVersion: "1.0",
                settingsRevision: 4,
                updatedAt: Date(timeIntervalSince1970: 1234),
                lastError: nil
            )
        )

        let data = try DaemonPayloadCodec.encode(snapshot)
        let decoded = try DaemonPayloadCodec.decode(DaemonSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, DaemonSnapshot.currentSchemaVersion)
    }

    @MainActor
    func testCapabilitiesDeriveLegacyFeatureMatrix() {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )

        XCTAssertTrue(capabilities.chargingControl)
        XCTAssertTrue(capabilities.directChargingControl)
        XCTAssertFalse(capabilities.firmwareChargeLimitControl)
        XCTAssertTrue(capabilities.sailingModeControl)
        XCTAssertTrue(capabilities.automaticDischargeControl)
        XCTAssertTrue(capabilities.forceDischargeControl)
        XCTAssertTrue(capabilities.chargeLimitOverrideControl)
        XCTAssertTrue(capabilities.sleepHooks)
        XCTAssertTrue(capabilities.heatProtectionControl)
        XCTAssertTrue(capabilities.magSafeLEDControl)
    }

    @MainActor
    func testCapabilitiesDeriveFirmwareFeatureMatrix() {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .firmware,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )

        XCTAssertTrue(capabilities.chargingControl)
        XCTAssertFalse(capabilities.directChargingControl)
        XCTAssertTrue(capabilities.firmwareChargeLimitControl)
        XCTAssertTrue(capabilities.sailingModeControl)
        XCTAssertFalse(capabilities.automaticDischargeControl)
        XCTAssertTrue(capabilities.forceDischargeControl)
        XCTAssertTrue(capabilities.chargeLimitOverrideControl)
        XCTAssertFalse(capabilities.sleepHooks)
        XCTAssertFalse(capabilities.heatProtectionControl)
        XCTAssertFalse(capabilities.magSafeLEDControl)
    }

    @MainActor
    func testCapabilitiesDeriveUnsupportedFeatureMatrix() {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .unsupported,
            adapterControl: false,
            magSafeLEDKeyAvailable: false
        )

        XCTAssertFalse(capabilities.chargingControl)
        XCTAssertFalse(capabilities.directChargingControl)
        XCTAssertFalse(capabilities.firmwareChargeLimitControl)
        XCTAssertFalse(capabilities.sailingModeControl)
        XCTAssertFalse(capabilities.automaticDischargeControl)
        XCTAssertFalse(capabilities.forceDischargeControl)
        XCTAssertFalse(capabilities.chargeLimitOverrideControl)
        XCTAssertFalse(capabilities.sleepHooks)
        XCTAssertFalse(capabilities.heatProtectionControl)
        XCTAssertFalse(capabilities.magSafeLEDControl)
    }
}
