import Foundation
import XCTest

final class DaemonSettingsStoreTests: XCTestCase {
    func testUserDefaultsBackendPersistsAcrossStoreRelaunch() async throws {
        let suiteName = "com.srimanachanta.stasis-daemon-tests.\(UUID().uuidString)"
        guard let firstDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated daemon settings defaults")
            return
        }
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }

        let firstStore = try DaemonSettingsStore(
            persistence: UserDefaultsDaemonSettingsPersistence(defaults: firstDefaults),
            capabilities: legacyCapabilities
        )
        let saved = try await firstStore.setSettings(settings(chargeLimit: 72))

        guard let relaunchedDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not reopen isolated daemon settings defaults")
            return
        }
        let relaunchedStore = try DaemonSettingsStore(
            persistence: UserDefaultsDaemonSettingsPersistence(defaults: relaunchedDefaults),
            capabilities: legacyCapabilities
        )

        let reloaded = await relaunchedStore.state()
        XCTAssertEqual(reloaded, saved)
    }

    func testSettingsPersistAcrossStoreRelaunch() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let firstStore = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: legacyCapabilities
        )
        let expected = settings(chargeLimit: 75)

        let saved = try await firstStore.setSettings(expected)
        let relaunchedStore = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: legacyCapabilities
        )
        let reloaded = await relaunchedStore.state()

        XCTAssertEqual(saved.settings, expected)
        XCTAssertEqual(reloaded, saved)
        XCTAssertFalse(reloaded.needsLegacyImport)
    }

    func testInvalidSettingsDoNotMutateOrPersistPartialState() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let store = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: legacyCapabilities
        )
        let before = await store.state()
        let persistedBefore = try persistence.load()
        var invalid = settings(chargeLimit: 80)
        invalid.chargeLimit = 101

        do {
            _ = try await store.setSettings(invalid)
            XCTFail("Expected invalid charge limit to be rejected")
        } catch {
            XCTAssertEqual(
                error as? DaemonSettingsValidationError,
                .chargeLimitOutOfRange(101)
            )
        }

        let after = await store.state()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try persistence.load(), persistedBefore)
    }

    func testEnabledSailingRejectsResumeThresholdBelowUIRangeWithoutPersisting() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let store = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: legacyCapabilities
        )
        let before = await store.state()
        let persistedBefore = try persistence.load()
        var invalid = settings(chargeLimit: 69)
        invalid.sailingDelta = 20

        do {
            _ = try await store.setSettings(invalid)
            XCTFail("Expected sailing threshold below 50% to be rejected")
        } catch {
            XCTAssertEqual(
                error as? DaemonSettingsValidationError,
                .invalidSailingThreshold(chargeLimit: 69, sailingDelta: 20)
            )
        }

        let after = await store.state()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try persistence.load(), persistedBefore)
    }

    func testEnabledSailingAcceptsResumeThresholdAtUIRangeBoundary() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: legacyCapabilities
        )
        var boundary = settings(chargeLimit: 70)
        boundary.sailingDelta = 20

        let saved = try await store.setSettings(boundary)

        XCTAssertEqual(saved.settings, boundary)
    }

    func testEnabledSailingRejectsZeroDelta() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: legacyCapabilities
        )
        var invalid = settings(chargeLimit: 80)
        invalid.sailingDelta = 0

        do {
            _ = try await store.setSettings(invalid)
            XCTFail("Expected enabled sailing with equal lower and upper limits to be rejected")
        } catch {
            XCTAssertEqual(
                error as? DaemonSettingsValidationError,
                .invalidSailingThreshold(chargeLimit: 80, sailingDelta: 0)
            )
        }
    }

    func testDisabledSailingDoesNotApplyResumeThresholdValidation() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: legacyCapabilities
        )
        var candidate = settings(chargeLimit: 50)
        candidate.sailingModeEnabled = false
        candidate.sailingDelta = 20

        let saved = try await store.setSettings(candidate)

        XCTAssertEqual(saved.settings, candidate)
    }

    func testPersistenceFailureKeepsLastConfirmedSettings() async throws {
        let persistence = InMemoryDaemonSettingsPersistence()
        let store = try DaemonSettingsStore(
            persistence: persistence,
            capabilities: legacyCapabilities
        )
        let before = await store.state()
        persistence.shouldFailSaves = true

        do {
            _ = try await store.setSettings(settings(chargeLimit: 70))
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error as? TestPersistenceError, .saveFailed)
        }

        let after = await store.state()
        XCTAssertEqual(after, before)
    }

    func testSuccessfulWritesIncrementRevision() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: legacyCapabilities
        )

        let first = try await store.setSettings(settings(chargeLimit: 75))
        let second = try await store.setSettings(settings(chargeLimit: 70))

        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(second.revision, 2)
    }

    func testLegacyImportRunsOnlyOnce() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: legacyCapabilities
        )
        let initial = await store.state()
        XCTAssertTrue(initial.needsLegacyImport)

        let imported = try await store.importLegacySettings(settings(chargeLimit: 75))
        let ignoredSecondImport = try await store.importLegacySettings(settings(chargeLimit: 60))

        XCTAssertFalse(imported.needsLegacyImport)
        XCTAssertEqual(imported.settings.chargeLimit, 75)
        XCTAssertEqual(ignoredSecondImport, imported)
    }

    func testFirmwareCapabilitiesNormalizeLegacyOnlySettings() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: firmwareCapabilities
        )
        var candidate = settings(chargeLimit: 80)
        candidate.automaticDischarge = true
        candidate.preventSleepUntilLimit = true
        candidate.heatProtectionEnabled = true
        candidate.manageMagSafeLED = true

        let result = try await store.setSettings(candidate).settings

        XCTAssertTrue(result.managementEnabled)
        XCTAssertTrue(result.sailingModeEnabled)
        XCTAssertFalse(result.automaticDischarge)
        XCTAssertFalse(result.preventSleepUntilLimit)
        XCTAssertFalse(result.heatProtectionEnabled)
        XCTAssertFalse(result.manageMagSafeLED)
    }

    func testUnsupportedCapabilitiesDisableManagement() async throws {
        let store = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: unsupportedCapabilities
        )

        let result = try await store.setSettings(settings(chargeLimit: 80)).settings

        XCTAssertFalse(result.managementEnabled)
        XCTAssertFalse(result.sailingModeEnabled)
        XCTAssertFalse(result.automaticDischarge)
    }

    private var legacyCapabilities: DaemonCapabilities {
        DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
    }

    private var firmwareCapabilities: DaemonCapabilities {
        DaemonCapabilities(
            chargeControlMode: .firmware,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
    }

    private var unsupportedCapabilities: DaemonCapabilities {
        DaemonCapabilities(
            chargeControlMode: .unsupported,
            adapterControl: false,
            magSafeLEDKeyAvailable: false
        )
    }

    private func settings(chargeLimit: Int) -> DaemonSettings {
        DaemonSettings(
            managementEnabled: true,
            chargeLimit: chargeLimit,
            sailingModeEnabled: true,
            sailingDelta: 5,
            automaticDischarge: true,
            preventSleepUntilLimit: true,
            heatProtectionEnabled: true,
            heatProtectionLimit: 40,
            manageMagSafeLED: true,
            heatProtectionLEDStateRawValue: 6
        )
    }
}

enum TestPersistenceError: Error, Equatable {
    case saveFailed
}

final class InMemoryDaemonSettingsPersistence: DaemonSettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var failSaves = false

    var shouldFailSaves: Bool {
        get { lock.withLock { failSaves } }
        set { lock.withLock { failSaves = newValue } }
    }

    func load() throws -> Data? {
        lock.withLock { storedData }
    }

    func save(_ data: Data) throws {
        try lock.withLock {
            guard !failSaves else { throw TestPersistenceError.saveFailed }
            storedData = data
        }
    }
}
