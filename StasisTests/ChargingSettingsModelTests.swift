import Observation
import XCTest

@testable import stasis

@MainActor
final class ChargingSettingsModelTests: XCTestCase {
    func testDoesNotCreatePlaceholderBeforeDaemonLoads() async {
        let client = MockChargingSettingsManager(loaded: false)
        let model = ChargingSettingsModel(client: client)
        defer { model.stop() }

        XCTAssertNil(model.managementState.settings)
        XCTAssertNil(model.thresholdState.settings)
        XCTAssertNil(model.batteryPercentageState.settings)
        XCTAssertFalse(model.isLoaded)
    }

    func testLoadsEachGroupFromDaemon() async {
        let model = ChargingSettingsModel(client: MockChargingSettingsManager())
        defer { model.stop() }

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.thresholdState.settings?.chargeLimit, 80)
        XCTAssertEqual(model.batteryPercentageState.settings?.useHardwarePercentage, false)
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

    func testThresholdCommitSendsOneWrite() async {
        let client = MockChargingSettingsManager()
        let model = ChargingSettingsModel(client: client)

        model.thresholdState.setChargeLimit(90)
        await waitForSaves(model)

        XCTAssertEqual(client.thresholdWrites.count, 1)
        XCTAssertEqual(client.thresholdWrites.first?.chargeLimit, 90)
    }

    func testThresholdInvariantIsAppliedWithinItsGroup() async {
        let client = MockChargingSettingsManager()
        client.chargingThresholdSettings = .init(
            chargeLimit: 80,
            sailingModeEnabled: true,
            sailingDelta: 20
        )
        let model = ChargingSettingsModel(client: client)

        model.thresholdState.setChargeLimit(50)
        await waitForSaves(model)

        XCTAssertEqual(model.threshold?.chargeLimit, 50)
        XCTAssertEqual(model.threshold?.sailingDelta, 0)
        XCTAssertEqual(model.threshold?.sailingModeEnabled, false)
    }

    func testSailingModeCanBeReenabledAfterChargeLimitWasSetToFifty() async {
        let client = MockChargingSettingsManager()
        let model = ChargingSettingsModel(client: client)
        defer { model.stop() }

        model.thresholdState.setChargeLimit(50)
        await waitForSaves(model)
        XCTAssertEqual(model.threshold?.chargeLimit, 50)
        XCTAssertFalse(model.threshold?.sailingModeEnabled ?? true)
        XCTAssertEqual(model.threshold?.sailingDelta, 0)

        model.thresholdState.setChargeLimit(80)
        await waitForSaves(model)
        model.thresholdState.setSailingEnabled(true)
        await waitForSaves(model)

        XCTAssertEqual(model.threshold?.chargeLimit, 80)
        XCTAssertTrue(model.threshold?.sailingModeEnabled ?? false)
        XCTAssertEqual(model.threshold?.sailingDelta, 5)
        XCTAssertEqual(
            client.thresholdWrites.last,
            .init(chargeLimit: 80, sailingModeEnabled: true, sailingDelta: 5)
        )
    }

    func testRapidChangesAreSerializedAndCoalescedToLatestValue() async {
        var writes: [Int] = []
        let state = ThresholdSettingsState(
            initialSettings: .init(),
            saveOperation: { value in
                writes.append(value.chargeLimit)
                if value.chargeLimit == 85 {
                    try? await Task.sleep(for: .milliseconds(40))
                }
                return value
            }
        )

        state.setChargeLimit(85)
        state.setChargeLimit(90)
        state.setChargeLimit(95)

        for _ in 0..<100 where state.isSaving {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(writes, [85, 95])
        XCTAssertEqual(state.settings?.chargeLimit, 95)
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
