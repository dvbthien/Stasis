import Foundation
import XCTest

final class ChargingSettingsStoreTests: XCTestCase {
    func testDefaults() async {
        let store = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())

        let management = await store.chargingManagementSettings()
        let threshold = await store.chargingThresholdSettings()
        let discharge = await store.automaticDischargeSettings()
        let sleep = await store.sleepPreventionSettings()
        let heat = await store.heatProtectionSettings()
        let led = await store.magSafeLEDSettings()
        let percentage = await store.batteryPercentageSettings()
        XCTAssertEqual(management, .init(isEnabled: false))
        XCTAssertEqual(threshold, .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5))
        XCTAssertEqual(discharge, .init(isEnabled: true))
        XCTAssertEqual(sleep, .init(isEnabled: false))
        XCTAssertEqual(heat, .init(isEnabled: true, temperatureLimit: 40))
        XCTAssertEqual(led, .init(isEnabled: true, heatProtectionState: .blinkOrangeSlow))
        XCTAssertEqual(percentage, .init(useHardwarePercentage: false))
    }

    func testPersistsEachGroupAcrossRestart() async throws {
        let persistence = InMemoryChargingSettingsPersistence()
        let store = ChargingSettingsStore(persistence: persistence)
        _ = await store.setChargingManagementSettings(.init(isEnabled: true))
        _ = try await store.setChargingThresholdSettings(.init(chargeLimit: 75, sailingModeEnabled: true, sailingDelta: 10))
        _ = await store.setBatteryPercentageSettings(.init(useHardwarePercentage: true))

        let relaunched = ChargingSettingsStore(persistence: persistence)
        let management = await relaunched.chargingManagementSettings()
        let threshold = await relaunched.chargingThresholdSettings()
        let percentage = await relaunched.batteryPercentageSettings()
        XCTAssertTrue(management.isEnabled)
        XCTAssertEqual(threshold.chargeLimit, 75)
        XCTAssertTrue(percentage.useHardwarePercentage)
    }

    func testInvalidThresholdIsRejectedWithoutChangingDesiredState() async {
        let store = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())
        do {
            _ = try await store.setChargingThresholdSettings(
                .init(chargeLimit: 55, sailingModeEnabled: true, sailingDelta: 10)
            )
            XCTFail("Expected invalid threshold")
        } catch {
            XCTAssertEqual(
                error as? ChargingSettingsValidationError,
                .invalidSailingThreshold(chargeLimit: 55, sailingDelta: 10)
            )
        }
        let current = await store.chargingThresholdSettings()
        XCTAssertEqual(current, .init())
    }

    func testCorruptThresholdOnlyResetsThresholdGroup() async throws {
        let persistence = InMemoryChargingSettingsPersistence()
        let store = ChargingSettingsStore(persistence: persistence)
        _ = await store.setChargingManagementSettings(.init(isEnabled: true))
        _ = await store.setBatteryPercentageSettings(.init(useHardwarePercentage: true))
        persistence.set(Data("broken".utf8), forKey: "charging.threshold.chargeLimit")

        let relaunched = ChargingSettingsStore(persistence: persistence)
        let threshold = await relaunched.chargingThresholdSettings()
        let management = await relaunched.chargingManagementSettings()
        let percentage = await relaunched.batteryPercentageSettings()
        XCTAssertEqual(threshold, .init())
        XCTAssertTrue(management.isEnabled)
        XCTAssertTrue(percentage.useHardwarePercentage)
    }

    func testCapabilitiesDoNotRewritePreferences() async {
        let store = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())
        _ = await store.setAutomaticDischargeSettings(.init(isEnabled: true))
        _ = await store.setMagSafeLEDSettings(.init(isEnabled: true, heatProtectionState: .blinkOrangeFast))

        let discharge = await store.automaticDischargeSettings()
        let led = await store.magSafeLEDSettings()
        XCTAssertTrue(discharge.isEnabled)
        XCTAssertTrue(led.isEnabled)
    }

    func testPolicyInputAssemblesGroupsAndPercentageChoice() async throws {
        let store = ChargingSettingsStore(persistence: InMemoryChargingSettingsPersistence())
        _ = try await store.setChargingThresholdSettings(.init(chargeLimit: 75, sailingModeEnabled: false, sailingDelta: 5))
        _ = await store.setAutomaticDischargeSettings(.init(isEnabled: false))
        _ = await store.setBatteryPercentageSettings(.init(useHardwarePercentage: true))
        let input = await store.makePolicyInput(chargeLimitOverrideActive: false)

        XCTAssertEqual(input.chargeLimit, 75)
        XCTAssertFalse(input.sailingModeEnabled)
        XCTAssertFalse(input.automaticDischarge)
        XCTAssertEqual(
            input.batteryPercentage(
                for: .init(batteryPercentage: 70, hardwareBatteryPercentage: 73, adapterConnected: true, batteryTemperature: 30)
            ),
            73
        )
    }
}

final class InMemoryChargingSettingsPersistence: ChargingSettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    func set(_ data: Data, forKey key: String) { lock.withLock { values[key] = data } }
    func removeObject(forKey key: String) { lock.withLock { values[key] = nil } }
}
