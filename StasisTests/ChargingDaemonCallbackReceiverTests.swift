import Foundation
import XCTest

@testable import stasis

final class ChargingDaemonCallbackReceiverTests: XCTestCase {
    @MainActor
    func testSnapshotAuthorityRejectsPreviousConnectionGeneration() {
        var authority = ChargingDaemonSnapshotAuthority()
        let firstGeneration = authority.beginConnection()
        authority.markAuthoritative(firstGeneration)
        XCTAssertTrue(authority.isAuthoritative)

        let secondGeneration = authority.beginConnection()
        XCTAssertFalse(authority.isAuthoritative)

        authority.markAuthoritative(firstGeneration)
        XCTAssertFalse(authority.isAuthoritative)

        authority.markAuthoritative(secondGeneration)
        XCTAssertTrue(authority.isAuthoritative)
    }

    @MainActor
    func testSnapshotAuthorityRevokesFreshnessForCurrentConnectionOnly() {
        var authority = ChargingDaemonSnapshotAuthority()
        let firstGeneration = authority.beginConnection()
        authority.markAuthoritative(firstGeneration)

        let secondGeneration = authority.beginConnection()
        authority.markAuthoritative(secondGeneration)
        authority.revoke(firstGeneration)
        XCTAssertTrue(authority.isAuthoritative)

        authority.revoke(secondGeneration)
        XCTAssertFalse(authority.isAuthoritative)
    }

    func testSnapshotCallbackCanArriveFromDetachedTask() async {
        let callbackReceived = expectation(description: "Snapshot callback received")
        let expectedPayload = Data([0x01, 0x02])
        let receiver = ChargingDaemonCallbackReceiver(
            stateDidChange: { payload in
                XCTAssertEqual(payload, expectedPayload)
                callbackReceived.fulfill()
            },
            settingsDidChange: { _ in }
        )

        await Task.detached {
            receiver.stateDidChange(expectedPayload)
        }.value

        await fulfillment(of: [callbackReceived], timeout: 1)
    }

    func testSettingsCallbackCanArriveFromDetachedTask() async {
        let callbackReceived = expectation(description: "Settings callback received")
        let expectedPayload = Data([0x03, 0x04])
        let receiver = ChargingDaemonCallbackReceiver(
            stateDidChange: { _ in },
            settingsDidChange: { payload in
                XCTAssertEqual(payload, expectedPayload)
                callbackReceived.fulfill()
            }
        )

        await Task.detached {
            receiver.settingsDidChange(expectedPayload)
        }.value

        await fulfillment(of: [callbackReceived], timeout: 1)
    }
}
