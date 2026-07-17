import XCTest

@testable import Stasis

@MainActor
final class ChargingNotificationTransitionTrackerTests: XCTestCase {
    func testTrackerEmitsOnlyDaemonDesiredChargingTransitions() {
        var tracker = ChargingNotificationTransitionTracker()

        XCTAssertEqual(
            tracker.process(snapshot: snapshot(desiredCharging: true)),
            ChargingNotificationTransition(charging: true, reason: "Below limit")
        )
        XCTAssertNil(tracker.process(snapshot: snapshot(desiredCharging: true)))
        XCTAssertEqual(
            tracker.process(snapshot: snapshot(desiredCharging: false)),
            ChargingNotificationTransition(charging: false, reason: "Below limit")
        )
    }

    func testTrackerDoesNotInferFirmwareChargingState() {
        var tracker = ChargingNotificationTransitionTracker()

        XCTAssertNil(tracker.process(snapshot: snapshot(desiredCharging: nil)))
    }

    func testTrackerResetsWhenManagementOrAdapterBecomesInactive() {
        var tracker = ChargingNotificationTransitionTracker()

        XCTAssertNotNil(tracker.process(snapshot: snapshot(desiredCharging: false)))
        XCTAssertNil(
            tracker.process(
                snapshot: snapshot(
                    desiredCharging: false,
                    managementEnabled: false
                )
            )
        )
        XCTAssertNotNil(tracker.process(snapshot: snapshot(desiredCharging: false)))

        XCTAssertNil(
            tracker.process(
                snapshot: snapshot(
                    desiredCharging: false,
                    adapterConnected: false
                )
            )
        )
        XCTAssertNotNil(tracker.process(snapshot: snapshot(desiredCharging: false)))
    }

    private func snapshot(
        desiredCharging: Bool?,
        managementEnabled: Bool = true,
        adapterConnected: Bool = true
    ) -> DaemonSnapshot {
        DaemonSnapshot(
            capabilities: DaemonCapabilities(
                chargeControlMode: desiredCharging == nil ? .firmware : .legacy,
                adapterControl: true,
                magSafeLEDKeyAvailable: true
            ),
            battery: DaemonBatterySnapshot(),
            adapter: DaemonAdapterSnapshot(
                physicallyConnected: adapterConnected
            ),
            hardware: DaemonHardwareState(),
            policy: DaemonPolicyState(
                managementEnabled: managementEnabled,
                desiredCharging: desiredCharging,
                reason: "Below limit"
            ),
            runtime: DaemonRuntimeState()
        )
    }
}
