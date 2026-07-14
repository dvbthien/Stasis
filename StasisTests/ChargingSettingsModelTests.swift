import Observation
import XCTest

@testable import stasis

@MainActor
final class ChargingSettingsModelTests: XCTestCase {
    func testDoesNotCreatePlaceholderBeforeDaemonLoads() {
        let client = MockChargingSettingsManager(loaded: false)
        let model = ChargingSettingsModel(client: client)

        XCTAssertNil(model.management)
        XCTAssertNil(model.threshold)
        XCTAssertNil(model.batteryPercentage)
        XCTAssertFalse(model.isLoaded)
    }

    func testLoadsEachGroupFromDaemon() {
        let model = ChargingSettingsModel(client: MockChargingSettingsManager())

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.threshold?.chargeLimit, 80)
        XCTAssertEqual(model.batteryPercentage?.useHardwarePercentage, false)
    }

    func testTracksDedicatedCapabilitiesProperty() async {
        let client = MockChargingSettingsManager()
        let initial = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        client.capabilities = initial
        let model = ChargingSettingsModel(client: client)

        XCTAssertEqual(model.capabilities, initial)

        let updated = DaemonCapabilities(
            chargeControlMode: .firmware,
            adapterControl: false,
            magSafeLEDKeyAvailable: false
        )
        client.capabilities = updated

        for _ in 0..<100 where model.capabilities != updated {
            await Task.yield()
        }

        XCTAssertEqual(model.capabilities, updated)
    }

    func testToggleSendsOnlyItsGroup() async {
        let client = MockChargingSettingsManager()
        let model = ChargingSettingsModel(client: client)

        model.setAutomaticDischargeEnabled(false)
        await waitForSaves(model)

        XCTAssertEqual(client.dischargeWrites, [.init(isEnabled: false)])
        XCTAssertTrue(client.thresholdWrites.isEmpty)
    }

    func testFailedGroupRollsBackWithoutChangingOtherGroups() async {
        let client = MockChargingSettingsManager()
        client.dischargeError = TestError.failed
        let model = ChargingSettingsModel(client: client)

        model.setAutomaticDischargeEnabled(false)
        model.setUseHardwarePercentage(true)
        await waitForSaves(model)

        XCTAssertEqual(model.automaticDischarge, .init(isEnabled: true))
        XCTAssertEqual(model.batteryPercentage, .init(useHardwarePercentage: true))
        XCTAssertNotNil(model.errorMessage)
    }

    func testSliderDebouncesThresholdWrites() async {
        let client = MockChargingSettingsManager()
        let model = ChargingSettingsModel(client: client, sliderDebounce: .milliseconds(20))

        model.updateChargingThreshold(debounced: true) { $0.chargeLimit = 85 }
        model.updateChargingThreshold(debounced: true) { $0.chargeLimit = 90 }
        try? await Task.sleep(for: .milliseconds(80))
        await waitForSaves(model)

        XCTAssertEqual(client.thresholdWrites.count, 1)
        XCTAssertEqual(client.thresholdWrites.first?.chargeLimit, 90)
    }

    func testDisableBeforeUninstallPersistsManagementOff() async throws {
        let client = MockChargingSettingsManager()
        client.chargingManagementSettings = .init(isEnabled: true)
        let model = ChargingSettingsModel(client: client)

        try await model.disableManagementForDaemonUninstall()

        XCTAssertEqual(client.managementWrites.last, .init(isEnabled: false))
        XCTAssertFalse(model.management?.isEnabled ?? true)
    }

    private func waitForSaves(_ model: ChargingSettingsModel) async {
        for _ in 0..<100 where model.isSaving {
            await Task.yield()
        }
    }
}

private enum TestError: Error { case failed }

@MainActor
@Observable
private final class MockChargingSettingsManager: ChargingSettingsManaging {
    var chargingManagementSettings: ChargingManagementSettings?
    var chargingThresholdSettings: ChargingThresholdSettings?
    var automaticDischargeSettings: AutomaticDischargeSettings?
    var sleepPreventionSettings: SleepPreventionSettings?
    var heatProtectionSettings: HeatProtectionSettings?
    var magSafeLEDSettings: MagSafeLEDSettings?
    var batteryPercentageSettings: BatteryPercentageSettings?
    var capabilities: DaemonCapabilities?

    var managementWrites: [ChargingManagementSettings] = []
    var thresholdWrites: [ChargingThresholdSettings] = []
    var dischargeWrites: [AutomaticDischargeSettings] = []
    var dischargeError: Error?

    init(loaded: Bool = true) {
        guard loaded else { return }
        chargingManagementSettings = .init()
        chargingThresholdSettings = .init()
        automaticDischargeSettings = .init()
        sleepPreventionSettings = .init()
        heatProtectionSettings = .init()
        magSafeLEDSettings = .init()
        batteryPercentageSettings = .init()
    }

    func setChargingManagementSettings(_ value: ChargingManagementSettings) async throws -> ChargingManagementSettings {
        managementWrites.append(value); chargingManagementSettings = value; return value
    }
    func setChargingThresholdSettings(_ value: ChargingThresholdSettings) async throws -> ChargingThresholdSettings {
        thresholdWrites.append(value); chargingThresholdSettings = value; return value
    }
    func setAutomaticDischargeSettings(_ value: AutomaticDischargeSettings) async throws -> AutomaticDischargeSettings {
        dischargeWrites.append(value)
        if let dischargeError { throw dischargeError }
        automaticDischargeSettings = value; return value
    }
    func setSleepPreventionSettings(_ value: SleepPreventionSettings) async throws -> SleepPreventionSettings { sleepPreventionSettings = value; return value }
    func setHeatProtectionSettings(_ value: HeatProtectionSettings) async throws -> HeatProtectionSettings { heatProtectionSettings = value; return value }
    func setMagSafeLEDSettings(_ value: MagSafeLEDSettings) async throws -> MagSafeLEDSettings { magSafeLEDSettings = value; return value }
    func setBatteryPercentageSettings(_ value: BatteryPercentageSettings) async throws -> BatteryPercentageSettings { batteryPercentageSettings = value; return value }
}
