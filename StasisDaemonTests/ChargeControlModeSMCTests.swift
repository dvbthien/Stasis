import XCTest
import smc_power

final class ChargeControlModeSMCTests: XCTestCase {
    func testWireChargeControlModeMapsFromSMCMode() {
        XCTAssertEqual(ChargeControlMode(smcMode: .unsupported), .unsupported)
        XCTAssertEqual(ChargeControlMode(smcMode: .legacy), .legacy)
        XCTAssertEqual(ChargeControlMode(smcMode: .firmware), .firmware)
    }
}
