import Foundation
import XCTest

final class BatteryManagementEngineTests: XCTestCase {
    func testLegacyBackendMatchesExistingPolicyDecisionAndWriteOrder() async throws {
        let fixture = try await makeFixture(
            mode: .legacy,
            settings: settings(automaticDischarge: true)
        )

        await fixture.runtime.handlePowerSourceUpdate(
            update(percentage: 81, temperature: 30)
        )

        let operations = await fixture.hardware.operations()
        XCTAssertEqual(
            operations,
            [.charging(false), .adapter(false), .led(3)]
        )

        let snapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertEqual(snapshot.policy.desiredCharging, false)
        XCTAssertEqual(snapshot.policy.desiredAdapter, false)
        XCTAssertEqual(snapshot.policy.desiredLEDStateRawValue, 3)
        XCTAssertEqual(
            snapshot.policy.reason,
            "Battery is above the charge limit of 80%"
        )
    }

    func testFirmwareBackendReconcilesLimitsWithoutLegacyWritesOrSleepHooks() async throws {
        let fixture = try await makeFixture(
            mode: .firmware,
            settings: settings(
                sailingModeEnabled: true,
                sailingDelta: 5,
                preventSleepUntilLimit: true
            )
        )

        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 60))

        let operations = await fixture.hardware.operations()
        let sleepUpdates = await fixture.sleepAssertion.updates()
        XCTAssertEqual(operations, [.firmwareLimit(lower: 75, upper: 80)])
        XCTAssertEqual(sleepUpdates, [])

        let snapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertNil(snapshot.policy.desiredCharging)
        XCTAssertNil(snapshot.policy.desiredAdapter)
        XCTAssertEqual(snapshot.hardware.firmwareChargeLimit?.lower, 75)
        XCTAssertEqual(snapshot.hardware.firmwareChargeLimit?.upper, 80)
    }

    func testLegacyPeriodicPassRepairsExternallyChangedChargingState() async throws {
        let fixture = try await makeFixture(
            mode: .legacy,
            settings: settings(automaticDischarge: false),
            periodicInterval: .milliseconds(20)
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 80))
        await fixture.hardware.simulateExternalChargingChange(enabled: true)

        try await Task.sleep(for: .milliseconds(70))

        let chargingEnabled = await fixture.hardware.isChargingEnabled()
        XCTAssertFalse(chargingEnabled)
        let disableWrites = await fixture.hardware.operations().filter {
            $0 == .charging(false)
        }
        XCTAssertEqual(disableWrites.count, 2)
    }

    func testFirmwarePeriodicPassRepairsExternallyChangedLimits() async throws {
        let fixture = try await makeFixture(
            mode: .firmware,
            settings: settings(sailingModeEnabled: false),
            periodicInterval: .milliseconds(20)
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 60))
        await fixture.hardware.simulateExternalFirmwareChange(
            active: false,
            lower: 0,
            upper: 100
        )

        try await Task.sleep(for: .milliseconds(70))

        let firmwareState = await fixture.hardware.firmwareState()
        XCTAssertEqual(
            firmwareState,
            DaemonFirmwareChargeLimitState(active: true, lower: 79, upper: 80)
        )
        let firmwareWrites = await fixture.hardware.operations().filter {
            $0 == .firmwareLimit(lower: 79, upper: 80)
        }
        XCTAssertEqual(firmwareWrites.count, 2)
        let containsLegacyWrite = await fixture.hardware.containsLegacyChargingWrite()
        XCTAssertFalse(containsLegacyWrite)
    }

    func testFirmwareWakeReconcilesLimitsWithoutLegacySleepHooks() async throws {
        let fixture = try await makeFixture(
            mode: .firmware,
            settings: settings(sailingModeEnabled: true, sailingDelta: 5)
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 60))
        await fixture.hardware.simulateExternalFirmwareChange(
            active: false,
            lower: 0,
            upper: 100
        )

        await fixture.runtime.handlePowerSourceUpdate(
            update(percentage: 60, reason: .wake)
        )

        let firmwareState = await fixture.hardware.firmwareState()
        let sleepUpdates = await fixture.sleepAssertion.updates()
        XCTAssertEqual(
            firmwareState,
            DaemonFirmwareChargeLimitState(active: true, lower: 75, upper: 80)
        )
        XCTAssertEqual(sleepUpdates, [])
    }

    func testFirmwareTemporaryCommandsRestoreCanonicalLimitAndAdapter() async throws {
        let fixture = try await makeFixture(
            mode: .firmware,
            settings: settings(sailingModeEnabled: true, sailingDelta: 5)
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 60))

        _ = try await fixture.runtime.setChargeLimitOverride(true)
        let overrideFirmwareActive = await fixture.hardware.firmwareState().active
        XCTAssertFalse(overrideFirmwareActive)
        _ = try await fixture.runtime.setChargeLimitOverride(false)
        let restoredAfterOverride = await fixture.hardware.firmwareState().active
        XCTAssertTrue(restoredAfterOverride)

        _ = try await fixture.runtime.setForceDischarge(true)
        let forcedAdapterEnabled = await fixture.hardware.isAdapterEnabled()
        let forcedFirmwareActive = await fixture.hardware.firmwareState().active
        XCTAssertFalse(forcedAdapterEnabled)
        XCTAssertFalse(forcedFirmwareActive)

        _ = try await fixture.runtime.setForceDischarge(false)
        let restoredAdapterEnabled = await fixture.hardware.isAdapterEnabled()
        let restoredFirmware = await fixture.hardware.firmwareState()
        XCTAssertTrue(restoredAdapterEnabled)
        XCTAssertEqual(
            restoredFirmware,
            DaemonFirmwareChargeLimitState(active: true, lower: 75, upper: 80)
        )
    }

    func testSettingsTriggerReevaluatesLegacyPolicy() async throws {
        let fixture = try await makeFixture(
            mode: .legacy,
            settings: settings(automaticDischarge: true)
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 70))

        var changedSettings = settings(automaticDischarge: true)
        changedSettings.chargeLimit = 60
        _ = try await fixture.settingsStore.setSettings(changedSettings)
        await fixture.runtime.settingsDidChange()

        let operations = await fixture.hardware.operations()
        XCTAssertTrue(operations.contains(.charging(false)))
        XCTAssertTrue(operations.contains(.adapter(false)))
    }

    func testAutomaticDischargeRefreshesDelayedTelemetryWithoutMenuDemand() async throws {
        let initialSettings = settings(automaticDischarge: false)
        let fixture = try await makeFixture(
            mode: .legacy,
            settings: initialSettings,
            delayedTelemetryRefreshDelay: .milliseconds(20),
            initialChargingEnabled: false,
            telemetryReadings: [
                telemetry(batteryPower: 11, adapterPower: 45),
                telemetry(batteryPower: 11, adapterPower: 45),
                telemetry(batteryPower: -8, adapterPower: 0),
            ]
        )
        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 81))

        var automaticDischargeSettings = initialSettings
        automaticDischargeSettings.automaticDischarge = true
        _ = try await fixture.settingsStore.setSettings(automaticDischargeSettings)
        await fixture.runtime.settingsDidChange()

        let immediateSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        let immediateTelemetryReadCount = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(immediateSnapshot.battery.power, 11)
        XCTAssertTrue(immediateSnapshot.battery.isCharging)
        XCTAssertEqual(immediateTelemetryReadCount, 2)

        try await Task.sleep(for: .milliseconds(60))

        let delayedSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        let telemetryReadCount = await fixture.hardware.telemetryReadCount()
        let telemetryActive = await fixture.runtime.isTelemetryActive()
        XCTAssertEqual(delayedSnapshot.battery.power, -8)
        XCTAssertEqual(delayedSnapshot.adapter.power, 0)
        XCTAssertFalse(delayedSnapshot.battery.isCharging)
        XCTAssertEqual(telemetryReadCount, 3)
        XCTAssertFalse(telemetryActive)
    }

    func testLegacySleepAssertionFollowsChargingDecision() async throws {
        let fixture = try await makeFixture(
            mode: .legacy,
            settings: settings(preventSleepUntilLimit: true)
        )

        await fixture.runtime.handlePowerSourceUpdate(update(percentage: 60))

        let updates = await fixture.sleepAssertion.updates()
        XCTAssertEqual(updates, [true])
    }

    func testMaintainLoopSerializesConcurrentTriggers() async throws {
        let loop = DaemonMaintainLoop()
        let probe = MaintainOperationProbe()
        await loop.start(periodicInterval: .seconds(10)) { _ in
            await probe.run()
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    await loop.request(index.isMultiple(of: 2) ? .powerSource : .settings)
                }
            }
        }

        let maximumConcurrentPasses = await probe.maximumConcurrentPasses()
        let passCount = await probe.passCount()
        XCTAssertEqual(maximumConcurrentPasses, 1)
        XCTAssertLessThanOrEqual(passCount, 2)
        await loop.stop()
    }

    private func makeFixture(
        mode: ChargeControlMode,
        settings: DaemonSettings,
        periodicInterval: Duration = .seconds(10),
        delayedTelemetryRefreshDelay: Duration = .seconds(3),
        initialChargingEnabled: Bool = true,
        telemetryReadings: [DaemonTelemetryReading] = []
    ) async throws -> (
        runtime: DaemonRuntimeCoordinator,
        hardware: EngineMockHardware,
        sleepAssertion: MockSleepAssertion,
        settingsStore: DaemonSettingsStore
    ) {
        let capabilities = DaemonCapabilities(
            chargeControlMode: mode,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let settingsStore = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: capabilities
        )
        _ = try await settingsStore.setSettings(settings)
        let stateStore = DaemonStateStore(
            capabilities: capabilities,
            daemonVersion: "test"
        )
        let hardware = EngineMockHardware(
            mode: mode,
            initialChargingEnabled: initialChargingEnabled,
            telemetryReadings: telemetryReadings
        )
        let clients = DaemonClientRegistry()
        let runtime = DaemonRuntimeCoordinator(
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            clients: clients,
            delayedTelemetryRefreshDelay: delayedTelemetryRefreshDelay
        )
        let sleepAssertion = MockSleepAssertion()
        let engine = BatteryManagementEngine(
            capabilities: capabilities,
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            runtime: runtime,
            sleepAssertion: sleepAssertion,
            periodicInterval: periodicInterval
        )
        await runtime.installManagementEngine(engine)
        return (runtime, hardware, sleepAssertion, settingsStore)
    }

    private func settings(
        sailingModeEnabled: Bool = false,
        sailingDelta: Int = 5,
        automaticDischarge: Bool = true,
        preventSleepUntilLimit: Bool = false
    ) -> DaemonSettings {
        DaemonSettings(
            managementEnabled: true,
            chargeLimit: 80,
            sailingModeEnabled: sailingModeEnabled,
            sailingDelta: sailingDelta,
            automaticDischarge: automaticDischarge,
            preventSleepUntilLimit: preventSleepUntilLimit,
            heatProtectionEnabled: true,
            heatProtectionLimit: 40,
            manageMagSafeLED: true,
            heatProtectionLEDStateRawValue: 6
        )
    }

    private func update(
        percentage: Int,
        temperature: Double = 30,
        reason: DaemonPowerSourceUpdateReason = .initial
    ) -> DaemonPowerSourceUpdate {
        DaemonPowerSourceUpdate(
            battery: DaemonBatterySnapshot(
                displayedPercentage: percentage,
                hardwarePercentage: percentage,
                temperature: temperature
            ),
            adapter: DaemonAdapterSnapshot(physicallyConnected: true),
            reason: reason
        )
    }

    private func telemetry(
        batteryPower: Double,
        adapterPower: Double
    ) -> DaemonTelemetryReading {
        DaemonTelemetryReading(
            batteryAvailable: true,
            adapterAvailable: true,
            batteryVoltage: 12.5,
            batteryCurrent: batteryPower / 12.5,
            batteryPower: batteryPower,
            adapterVoltage: adapterPower == 0 ? 0 : 20,
            adapterCurrent: adapterPower / 20,
            adapterPower: adapterPower
        )
    }
}

private enum EngineHardwareOperation: Equatable, Sendable {
    case charging(Bool)
    case adapter(Bool)
    case led(UInt8)
    case firmwareLimit(lower: Int, upper: Int)
    case firmwareDisabled
}

private actor EngineMockHardware: DaemonHardwareControlling {
    private let mode: ChargeControlMode
    private var recordedOperations: [EngineHardwareOperation] = []
    private var chargingEnabled = true
    private var adapterEnabled = true
    private var ledRawValue: UInt8 = 0
    private var firmware = DaemonFirmwareChargeLimitState(
        active: false,
        lower: 0,
        upper: 100
    )
    private let telemetryReadings: [DaemonTelemetryReading]
    private var telemetryReads = 0

    init(
        mode: ChargeControlMode,
        initialChargingEnabled: Bool,
        telemetryReadings: [DaemonTelemetryReading]
    ) {
        self.mode = mode
        chargingEnabled = initialChargingEnabled
        self.telemetryReadings = telemetryReadings
    }

    func setChargingEnabled(_ enabled: Bool) throws -> Bool {
        guard chargingEnabled != enabled else { return false }
        chargingEnabled = enabled
        recordedOperations.append(.charging(enabled))
        return true
    }

    func setAdapterEnabled(_ enabled: Bool) throws -> Bool {
        guard adapterEnabled != enabled else { return false }
        adapterEnabled = enabled
        recordedOperations.append(.adapter(enabled))
        return true
    }

    func setMagSafeLED(rawValue: UInt8) throws -> Bool {
        guard ledRawValue != rawValue else { return false }
        ledRawValue = rawValue
        recordedOperations.append(.led(rawValue))
        return true
    }

    func ensureFirmwareChargeLimit(lower: Int, upper: Int) throws -> Bool {
        let desired = DaemonFirmwareChargeLimitState(
            active: true,
            lower: lower,
            upper: upper
        )
        guard firmware != desired else { return false }
        firmware = desired
        recordedOperations.append(.firmwareLimit(lower: lower, upper: upper))
        return true
    }

    func ensureFirmwareChargeLimitDisabled() throws -> Bool {
        guard firmware.active else { return false }
        firmware.active = false
        recordedOperations.append(.firmwareDisabled)
        return true
    }

    func readHardwareState() -> DaemonHardwareState {
        DaemonHardwareState(
            chargingInhibited: mode == .legacy ? !chargingEnabled : nil,
            forceDischarging: !adapterEnabled,
            magSafeLEDStateRawValue: ledRawValue,
            firmwareChargeLimit: mode == .firmware ? firmware : nil
        )
    }

    func readTelemetry() -> DaemonTelemetryReading {
        telemetryReads += 1
        guard !telemetryReadings.isEmpty else { return DaemonTelemetryReading() }
        let index = min(telemetryReads - 1, telemetryReadings.count - 1)
        return telemetryReadings[index]
    }

    func resetToDefaults() {}

    func operations() -> [EngineHardwareOperation] {
        recordedOperations
    }

    func telemetryReadCount() -> Int {
        telemetryReads
    }

    func isChargingEnabled() -> Bool {
        chargingEnabled
    }

    func isAdapterEnabled() -> Bool {
        adapterEnabled
    }

    func firmwareState() -> DaemonFirmwareChargeLimitState {
        firmware
    }

    func containsLegacyChargingWrite() -> Bool {
        recordedOperations.contains {
            if case .charging = $0 { true } else { false }
        }
    }

    func simulateExternalChargingChange(enabled: Bool) {
        chargingEnabled = enabled
    }

    func simulateExternalFirmwareChange(active: Bool, lower: Int, upper: Int) {
        firmware = DaemonFirmwareChargeLimitState(
            active: active,
            lower: lower,
            upper: upper
        )
    }
}

private actor MockSleepAssertion: DaemonSleepAssertionControlling {
    private var values: [Bool] = []

    func update(shouldPreventSleep: Bool) {
        values.append(shouldPreventSleep)
    }

    func updates() -> [Bool] {
        values
    }
}

private actor MaintainOperationProbe {
    private var activePasses = 0
    private var maximumActivePasses = 0
    private var completedPasses = 0

    func run() async {
        activePasses += 1
        maximumActivePasses = max(maximumActivePasses, activePasses)
        try? await Task.sleep(for: .milliseconds(20))
        activePasses -= 1
        completedPasses += 1
    }

    func maximumConcurrentPasses() -> Int {
        maximumActivePasses
    }

    func passCount() -> Int {
        completedPasses
    }
}
