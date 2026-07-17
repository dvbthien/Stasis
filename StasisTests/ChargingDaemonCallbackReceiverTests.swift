import XCTest

@testable import Stasis

final class ChargingDaemonCallbackReceiverTests: XCTestCase {
    func testForwardsSnapshotPayload() async {
        let expected = Data([1, 2, 3])
        let received = expectation(description: "snapshot callback")
        let receiver = ChargingDaemonCallbackReceiver { payload in
            XCTAssertEqual(payload, expected)
            received.fulfill()
        }

        receiver.stateDidChange(expected)

        await fulfillment(of: [received], timeout: 1)
    }
}
