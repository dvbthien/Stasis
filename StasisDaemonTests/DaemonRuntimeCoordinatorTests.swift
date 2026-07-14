import Foundation
import XCTest

final class DaemonRuntimeCoordinatorTests: XCTestCase {
    func testIOKitUpdatePublishesImmediately() async throws {
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
        XCTAssertEqual(snapshot.battery.voltage, 0)
        XCTAssertEqual(snapshot.battery.power, 0)
        XCTAssertFalse(snapshot.battery.isCharging)
        XCTAssertEqual(snapshot.adapter.power, 0)
        let hardwareStateReads = await fixture.hardware.hardwareStateReadCount()
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

    func testPowerSourceUpdatePreservesIOKitChargingState() async throws {
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

        let settingsState = await settingsStore.state()
        let snapshot = await stateStore.snapshot(settingsState: settingsState)
        XCTAssertTrue(snapshot.battery.isCharging)
    }

    func testAdapterTransitionPublishesImmediatelyWithoutTelemetryFollowUp() async throws {
        let fixture = try makeFixture()
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
        XCTAssertFalse(immediateSnapshot.adapter.physicallyConnected)
        XCTAssertEqual(client.snapshotCount(), 2)
    }

    func testHardwareChangePublishesSingleRefreshedSnapshot() async throws {
        let fixture = try makeFixture()
        let client = SnapshotCaptureClient()
        fixture.clients.add(client, id: UUID())

        await fixture.runtime.reconcilePolicyAfterHardwareCommand()
        XCTAssertEqual(client.snapshotCount(), 1)
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

    func testHardwareChangeRefreshesIOKitImmediatelyOnly() async throws {
        let fixture = try makeFixture()
        let source = RuntimeIOKitRefreshSource(updates: [
            DaemonPowerSourceUpdate(
                battery: DaemonBatterySnapshot(displayedPercentage: 60),
                adapter: DaemonAdapterSnapshot(physicallyConnected: true),
                reason: .hardwareRefresh
            )
        ])
        await fixture.runtime.installIOKitRefreshHandler { reason in
            await source.refresh(reason: reason)
        }

        await fixture.runtime.reconcilePolicyAfterHardwareCommand()
        let immediateSnapshot = await fixture.runtime.currentSnapshot(refreshHardware: false)
        XCTAssertEqual(immediateSnapshot.battery.displayedPercentage, 60)

        let reasons = await source.requestedReasons()
        XCTAssertEqual(reasons, [.hardwareRefresh])
    }

    private func makeFixture() throws -> (
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
            clients: clients
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
