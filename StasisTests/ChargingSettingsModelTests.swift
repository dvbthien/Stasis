import Observation
import XCTest

@testable import stasis

@MainActor
final class ChargingSettingsModelTests: XCTestCase {
    func testModelStartsFromDaemonCanonicalSettingsAcrossAppModelRelaunch() async {
        let canonical = DaemonSettings(
            managementEnabled: true,
            chargeLimit: 73,
            useHardwarePercentage: true
        )
        let client = MockChargingSettingsManager(settings: canonical)

        let firstModel = ChargingSettingsModel(client: client)
        let relaunchedModel = ChargingSettingsModel(client: client)

        XCTAssertTrue(firstModel.isLoaded)
        XCTAssertEqual(firstModel.settings, canonical)
        XCTAssertEqual(relaunchedModel.settings, canonical)
        firstModel.stop()
        relaunchedModel.stop()
        await Task.yield()
    }

    func testImmediateEditSendsFullPayloadAndAppliesCanonicalResponse() async throws {
        var initial = DaemonSettings(managementEnabled: true, chargeLimit: 80)
        initial.sailingDelta = 5
        let client = MockChargingSettingsManager(settings: initial)
        client.canonicalize = { request in
            var canonical = request
            canonical.chargeLimit = 75
            return canonical
        }
        let model = ChargingSettingsModel(client: client)

        model.set(\.automaticDischarge, to: false)
        try await waitUntil { !model.isSaving && client.savedSettings.count == 1 }

        XCTAssertEqual(client.savedSettings.first?.sailingDelta, 5)
        XCTAssertEqual(client.savedSettings.first?.automaticDischarge, false)
        XCTAssertEqual(model.settings.chargeLimit, 75)
        XCTAssertEqual(model.settings, client.daemonSettingsState?.settings)
        model.stop()
    }

    func testSliderEditsAreDebouncedAndCoalesced() async throws {
        let client = MockChargingSettingsManager(
            settings: DaemonSettings(managementEnabled: true, chargeLimit: 80)
        )
        let model = ChargingSettingsModel(
            client: client,
            sliderDebounce: .milliseconds(40)
        )

        model.set(\.chargeLimit, to: 75, debounced: true)
        try await Task.sleep(for: .milliseconds(10))
        model.set(\.chargeLimit, to: 70, debounced: true)

        try await waitUntil { !model.isSaving && client.savedSettings.count == 1 }
        XCTAssertEqual(client.savedSettings.map(\.chargeLimit), [70])
        XCTAssertEqual(model.settings.chargeLimit, 70)
        model.stop()
    }

    func testSaveFailureRollsBackToLastConfirmedSettings() async throws {
        let confirmed = DaemonSettings(
            managementEnabled: true,
            chargeLimit: 80,
            automaticDischarge: true
        )
        let client = MockChargingSettingsManager(settings: confirmed)
        client.saveError = MockChargingSettingsError.rejected
        let model = ChargingSettingsModel(client: client)

        model.set(\.automaticDischarge, to: false)
        XCTAssertFalse(model.settings.automaticDischarge)

        try await waitUntil { model.errorMessage != nil && !model.isSaving }
        XCTAssertEqual(model.settings, confirmed)
        XCTAssertEqual(client.daemonSettingsState?.settings, confirmed)
        XCTAssertEqual(client.savedSettings.count, 1)
        model.stop()
    }

    func testManagementToggleWaitsForDaemonConfirmation() async throws {
        let client = MockChargingSettingsManager(settings: DaemonSettings())
        client.saveDelay = .milliseconds(60)
        let model = ChargingSettingsModel(client: client)

        model.setManagementEnabled(true)

        XCTAssertFalse(model.settings.managementEnabled)
        try await waitUntil { client.savedSettings.count == 1 }
        XCTAssertFalse(model.settings.managementEnabled)

        try await waitUntil { !model.isSaving && model.settings.managementEnabled }
        XCTAssertTrue(client.daemonSettingsState?.settings.managementEnabled == true)
        model.stop()
    }

    func testDaemonUninstallPreparationPersistsManagementDisabled() async throws {
        let client = MockChargingSettingsManager(
            settings: DaemonSettings(managementEnabled: true, chargeLimit: 75)
        )
        let model = ChargingSettingsModel(client: client)

        try await model.disableManagementForDaemonUninstall()

        XCTAssertFalse(model.settings.managementEnabled)
        XCTAssertFalse(client.daemonSettingsState?.settings.managementEnabled ?? true)
        XCTAssertEqual(client.savedSettings.count, 1)
        XCTAssertEqual(client.savedSettings.first?.chargeLimit, 75)
        model.stop()
    }

    func testDaemonUninstallPreparationRollsBackWhenSaveFails() async {
        let confirmed = DaemonSettings(managementEnabled: true, chargeLimit: 80)
        let client = MockChargingSettingsManager(settings: confirmed)
        client.saveError = MockChargingSettingsError.rejected
        let model = ChargingSettingsModel(client: client)

        do {
            try await model.disableManagementForDaemonUninstall()
            XCTFail("Expected uninstall preparation to fail")
        } catch {
            XCTAssertEqual(model.settings, confirmed)
            XCTAssertNotNil(model.errorMessage)
        }

        model.stop()
    }

    func testCapabilityAvailabilityDisablesLegacyOnlyFirmwareFeatures() {
        let unresolved = ChargingSettingsAvailability(capabilities: nil)
        XCTAssertFalse(unresolved.isResolved)
        XCTAssertFalse(unresolved.management)
        XCTAssertTrue(unresolved.canAttemptManagement)

        let legacy = ChargingSettingsAvailability(
            capabilities: capabilities(mode: .legacy)
        )
        XCTAssertTrue(legacy.isResolved)
        XCTAssertTrue(legacy.canAttemptManagement)
        XCTAssertTrue(legacy.management)
        XCTAssertTrue(legacy.automaticDischarge)
        XCTAssertTrue(legacy.sleepPrevention)
        XCTAssertTrue(legacy.heatProtection)
        XCTAssertTrue(legacy.magSafeLED)

        let firmware = ChargingSettingsAvailability(
            capabilities: capabilities(mode: .firmware)
        )
        XCTAssertTrue(firmware.management)
        XCTAssertTrue(firmware.sailingMode)
        XCTAssertFalse(firmware.automaticDischarge)
        XCTAssertFalse(firmware.sleepPrevention)
        XCTAssertFalse(firmware.heatProtection)
        XCTAssertFalse(firmware.magSafeLED)

        let unsupported = ChargingSettingsAvailability(
            capabilities: capabilities(mode: .unsupported)
        )
        XCTAssertTrue(unsupported.isResolved)
        XCTAssertFalse(unsupported.canAttemptManagement)
        XCTAssertFalse(unsupported.management)
        XCTAssertFalse(unsupported.sailingMode)
    }

    private func capabilities(mode: ChargeControlMode) -> DaemonCapabilities {
        DaemonCapabilities(
            chargeControlMode: mode,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous settings state")
    }
}

private enum MockChargingSettingsError: Error {
    case rejected
}

@MainActor
@Observable
private final class MockChargingSettingsManager: ChargingSettingsManaging {
    var daemonSettingsState: DaemonSettingsState?
    var daemonSnapshot: DaemonSnapshot?
    var savedSettings: [DaemonSettings] = []
    var saveDelay: Duration?
    var saveError: Error?
    var canonicalize: (DaemonSettings) -> DaemonSettings = { $0 }

    init(settings: DaemonSettings) {
        daemonSettingsState = DaemonSettingsState(
            settings: settings,
            revision: 1,
            needsLegacyImport: false
        )
    }

    func synchronizeChargingSettings(
        _ settings: DaemonSettings
    ) async throws -> DaemonSettingsState {
        savedSettings.append(settings)
        if let saveDelay {
            try await Task.sleep(for: saveDelay)
        }
        if let saveError {
            throw saveError
        }

        let state = DaemonSettingsState(
            settings: canonicalize(settings),
            revision: (daemonSettingsState?.revision ?? 0) + 1,
            needsLegacyImport: false
        )
        daemonSettingsState = state
        return state
    }
}
