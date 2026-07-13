import Foundation
import XCTest

final class DaemonRuntimeCoordinatorTests: XCTestCase {
    func testIOKitUpdatePublishesImmediatelyWhilePreservingCachedTelemetry() async throws {
        let fixture = try makeFixture()
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.handlePowerSourceUpdate(update(reason: .initial))

        await fixture.runtime.handlePowerSourceUpdate(
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(
                    displayedPercentage: 64,
                    hardwarePercentage: 62,
                    isCharging: false,
                    timeRemaining: 90,
                    temperature: 34,
                    health: 93,
                    cycleCount: 180
                ),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .interestNotification
            )
        )

        let snapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertEqual(snapshot.battery.displayedPercentage, 64)
        XCTAssertEqual(snapshot.battery.hardwarePercentage, 62)
        XCTAssertEqual(snapshot.battery.voltage, 12.5)
        XCTAssertEqual(snapshot.battery.power, 11)
        XCTAssertFalse(snapshot.battery.isCharging)
        XCTAssertEqual(snapshot.adapter.power, 45)
        let telemetryReads = await fixture.hardware.telemetryReadCount()
        let hardwareStateReads = await fixture.hardware.hardwareStateReadCount()
        XCTAssertEqual(telemetryReads, 1)
        XCTAssertEqual(hardwareStateReads, 1)

        let published = try XCTUnwrap(client.latestSnapshot())
        XCTAssertEqual(published.battery, snapshot.battery)
        XCTAssertEqual(published.adapter, snapshot.adapter)
    }

    func testInitialAndWakeUpdatesRefreshHardwareState() async throws {
        let fixture = try makeFixture()

        await fixture.runtime.handlePowerSourceUpdate(update(reason: .initial))
        await fixture.runtime.handlePowerSourceUpdate(update(reason: .interestNotification))
        await fixture.runtime.handlePowerSourceUpdate(update(reason: .wake))

        let hardwareStateReads = await fixture.hardware.hardwareStateReadCount()
        XCTAssertEqual(hardwareStateReads, 2)
        let snapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertEqual(snapshot.adapter.powerEnabled, true)
        XCTAssertEqual(snapshot.runtime.status, .ready)
    }

    func testUnavailableSMCTelemetryPreservesIOKitChargingState() async throws {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let settingsStore = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: capabilities
        )
        let stateStore = DaemonStateStore(
            capabilities: capabilities,
            daemonVersion: "test"
        )

        await stateStore.updatePowerSource(
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(isCharging: true),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .interestNotification
            )
        )
        await stateStore.updateTelemetry(DaemonTelemetryReading())

        let settingsState = await settingsStore.state()
        let snapshot = await stateStore.snapshot(settingsState: settingsState)
        XCTAssertTrue(snapshot.battery.isCharging)
    }

    func testAdapterTransitionPublishesImmediatelyThenRefreshesTelemetryLater() async throws {
        let fixture = try makeFixture(delayedTelemetryRefreshDelay: .milliseconds(20))
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.handlePowerSourceUpdate(update(reason: .initial))
        XCTAssertEqual(client.snapshotCount(), 1)

        await fixture.runtime.handlePowerSourceUpdate(
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 49),
                adapter: DaemonAdapterSnapshot(physicallyConnected: false),
                reason: .interestNotification
            )
        )

        let immediateSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        let immediateReads = await fixture.hardware.telemetryReadCount()
        XCTAssertFalse(immediateSnapshot.adapter.physicallyConnected)
        XCTAssertEqual(immediateReads, 1)
        XCTAssertEqual(client.snapshotCount(), 2)

        try await Task.sleep(for: .milliseconds(60))
        let delayedReads = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(delayedReads, 2)
        XCTAssertEqual(client.snapshotCount(), 3)
    }

    func testInterestUpdateWithoutAdapterTransitionRefreshesTelemetryFollowUp() async throws {
        let fixture = try makeFixture(delayedTelemetryRefreshDelay: .milliseconds(20))
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.handlePowerSourceUpdate(update(reason: .initial))
        await fixture.runtime.handlePowerSourceUpdate(
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 49),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .interestNotification
            )
        )

        try await Task.sleep(for: .milliseconds(60))

        let telemetryReads = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(telemetryReads, 2)
        XCTAssertEqual(client.snapshotCount(), 3)
    }

    func testInterestUpdatesDebounceDelayedTelemetryRefresh() async throws {
        let fixture = try makeFixture(delayedTelemetryRefreshDelay: .milliseconds(30))
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.handlePowerSourceUpdate(update(reason: .initial))
        await fixture.runtime.handlePowerSourceUpdate(update(reason: .interestNotification))
        try await Task.sleep(for: .milliseconds(10))
        await fixture.runtime.handlePowerSourceUpdate(update(reason: .interestNotification))

        try await Task.sleep(for: .milliseconds(70))

        let telemetryReads = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(telemetryReads, 2)
        XCTAssertEqual(client.snapshotCount(), 4)
    }

    func testHardwareChangeGetsDelayedTelemetryFollowUp() async throws {
        let fixture = try makeFixture(delayedTelemetryRefreshDelay: .milliseconds(20))
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.reconcilePolicyAfterHardwareCommand()
        let immediateReads = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(immediateReads, 1)
        XCTAssertEqual(client.snapshotCount(), 1)

        try await Task.sleep(for: .milliseconds(60))
        let delayedReads = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(delayedReads, 2)
        XCTAssertEqual(client.snapshotCount(), 2)
    }

    func testTelemetryLoopRemainsActiveUntilLastClientReleasesDemand() async throws {
        let fixture = try makeFixture(telemetryInterval: .milliseconds(15))
        let firstClient = UUID()
        let secondClient = UUID()

        await fixture.runtime.setTelemetryActive(true, for: firstClient)
        await fixture.runtime.setTelemetryActive(true, for: secondClient)
        try await Task.sleep(for: .milliseconds(55))

        let activeAfterBothClients = await fixture.runtime.isTelemetryActive()
        XCTAssertTrue(activeAfterBothClients)
        let activeReadCount = await fixture.hardware.telemetryReadCount()
        XCTAssertGreaterThanOrEqual(activeReadCount, 3)

        await fixture.runtime.setTelemetryActive(false, for: firstClient)
        let activeAfterFirstClient = await fixture.runtime.isTelemetryActive()
        XCTAssertTrue(activeAfterFirstClient)

        await fixture.runtime.clientDisconnected(secondClient)
        let activeAfterDisconnect = await fixture.runtime.isTelemetryActive()
        XCTAssertFalse(activeAfterDisconnect)
        let stoppedReadCount = await fixture.hardware.telemetryReadCount()
        try await Task.sleep(for: .milliseconds(45))
        let finalReadCount = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(finalReadCount, stoppedReadCount)
    }

    func testFirstTelemetryClientGetsImmediateSnapshotWithoutDuplicatingLoop() async throws {
        let fixture = try makeFixture()
        let client = SnapshotCaptureClient()
        let firstClientID = UUID()
        let secondClientID = UUID()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.setTelemetryActive(true, for: firstClientID)

        let initialReadCount = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(initialReadCount, 1)
        XCTAssertEqual(client.snapshotCount(), 1)

        await fixture.runtime.setTelemetryActive(true, for: firstClientID)
        await fixture.runtime.setTelemetryActive(true, for: secondClientID)

        let readCountAfterRepeatedDemand = await fixture.hardware.telemetryReadCount()
        XCTAssertEqual(readCountAfterRepeatedDemand, 1)
        XCTAssertEqual(client.snapshotCount(), 1)

        await fixture.runtime.setTelemetryActive(false, for: firstClientID)
        await fixture.runtime.setTelemetryActive(false, for: secondClientID)
    }

    func testSettingsChangeRefreshesIOKitSnapshotBeforePublishing() async throws {
        let fixture = try makeFixture()
        let source = RuntimeIOKitRefreshSource(updates: [
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(
                    displayedPercentage: 67,
                    hardwarePercentage: 65,
                    temperature: 36
                ),
                adapter: DaemonAdapterSnapshot(physicallyConnected: false),
                reason: .settingsRefresh
            )
        ])
        await fixture.runtime.installIOKitRefreshHandler { reason in
            await source.refresh(reason: reason)
        }

        await fixture.runtime.reconcilePolicyAfterSettingsChange()

        let snapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        let reasons = await source.requestedReasons()
        XCTAssertEqual(reasons, [.settingsRefresh])
        XCTAssertEqual(snapshot.battery.displayedPercentage, 67)
        XCTAssertEqual(snapshot.battery.hardwarePercentage, 65)
        XCTAssertEqual(snapshot.battery.temperature, 36)
        XCTAssertFalse(snapshot.adapter.physicallyConnected)
    }

    func testHardwareChangeRefreshesIOKitImmediatelyAndAfterSettleDelay() async throws {
        let fixture = try makeFixture(delayedTelemetryRefreshDelay: .milliseconds(20))
        let source = RuntimeIOKitRefreshSource(updates: [
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 60),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .hardwareRefresh
            ),
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 61),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .hardwareRefresh
            ),
        ])
        await fixture.runtime.installIOKitRefreshHandler { reason in
            await source.refresh(reason: reason)
        }

        await fixture.runtime.reconcilePolicyAfterHardwareCommand()
        let immediateSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertEqual(immediateSnapshot.battery.displayedPercentage, 60)

        try await Task.sleep(for: .milliseconds(60))

        let delayedSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        let reasons = await source.requestedReasons()
        XCTAssertEqual(delayedSnapshot.battery.displayedPercentage, 61)
        XCTAssertEqual(reasons, [.hardwareRefresh, .hardwareRefresh])
    }

    private func makeFixture(
        telemetryInterval: Duration = .seconds(1),
        delayedTelemetryRefreshDelay: Duration = .seconds(3)
    ) throws -> (
        runtime: DaemonRuntimeCoordinator,
        hardware: RuntimeMockHardware,
        clients: DaemonClientRegistry
    ) {
        let capabilities = DaemonCapabilities(
            chargeControlMode: .legacy,
            adapterControl: true,
            magSafeLEDKeyAvailable: true
        )
        let settingsStore = try DaemonSettingsStore(
            persistence: InMemoryDaemonSettingsPersistence(),
            capabilities: capabilities
        )
        let stateStore = DaemonStateStore(
            capabilities: capabilities,
            daemonVersion: "test"
        )
        let hardware = RuntimeMockHardware()
        let clients = DaemonClientRegistry()
        let runtime = DaemonRuntimeCoordinator(
            settingsStore: settingsStore,
            stateStore: stateStore,
            hardware: hardware,
            clients: clients,
            telemetryInterval: telemetryInterval,
            delayedTelemetryRefreshDelay: delayedTelemetryRefreshDelay
        )
        return (runtime, hardware, clients)
    }

    private func update(reason: DaemonPowerSourceUpdateReason) -> DaemonPowerSourceUpdate {
        DaemonPowerSourceUpdate(
            battery: DaemonBatterySnapshot(displayedPercentage: 50),
            adapter: DaemonAdapterSnapshot(physicallyConnected: true),
            reason: reason
        )
    }
}

private actor RuntimeMockHardware: DaemonHardwareControlling {
    private var telemetryReads = 0
    private var hardwareStateReads = 0

    func setChargingEnabled(_ enabled: Bool) async throws -> Bool { false }
    func setAdapterEnabled(_ enabled: Bool) async throws -> Bool { false }
    func setMagSafeLED(rawValue: UInt8) async throws -> Bool { false }

    func readHardwareState() async throws -> DaemonHardwareState {
        hardwareStateReads += 1
        return DaemonHardwareState(
            chargingInhibited: false,
            forceDischarging: false,
            magSafeLEDStateRawValue: 3
        )
    }

    func readTelemetry() async -> DaemonTelemetryReading {
        telemetryReads += 1
        return DaemonTelemetryReading(
            batteryAvailable: true,
            adapterAvailable: true,
            batteryVoltage: 12.5,
            batteryCurrent: 0.88,
            batteryPower: 11,
            adapterVoltage: 20,
            adapterCurrent: 2.25,
            adapterPower: 45
        )
    }

    func telemetryReadCount() -> Int {
        telemetryReads
    }

    func hardwareStateReadCount() -> Int {
        hardwareStateReads
    }
}

private final class SnapshotCaptureClient: NSObject, ChargingDaemonClientProtocol,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var snapshots: [DaemonSnapshot] = []

    nonisolated func stateDidChange(_ payload: Data) {
        guard let decoded = try? DaemonPayloadCodec.decode(DaemonSnapshot.self, from: payload) else {
            return
        }
        lock.withLock {
            snapshots.append(decoded)
        }
    }

    nonisolated func settingsDidChange(_ payload: Data) {}

    func latestSnapshot() -> DaemonSnapshot? {
        lock.withLock { snapshots.last }
    }

    func snapshotCount() -> Int {
        lock.withLock { snapshots.count }
    }
}

private actor RuntimeIOKitRefreshSource {
    private var updates: [DaemonPowerSourceUpdate]
    private var reasons: [DaemonPowerSourceUpdateReason] = []

    init(updates: [DaemonPowerSourceUpdate]) {
        self.updates = updates
    }

    func refresh(reason: DaemonPowerSourceUpdateReason) -> DaemonPowerSourceUpdate? {
        reasons.append(reason)
        guard !updates.isEmpty else { return nil }
        var update = updates.removeFirst()
        update.reason = reason
        return update
    }

    func requestedReasons() -> [DaemonPowerSourceUpdateReason] {
        reasons
    }
}
