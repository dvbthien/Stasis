import Foundation
import XCTest

@testable import stasis

final class ChargingDaemonCallbackReceiverTests: XCTestCase {
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
