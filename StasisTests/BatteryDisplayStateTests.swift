import XCTest

@testable import Stasis

final class BatteryDisplayStateTests: XCTestCase {
    @MainActor
    func testDisconnectedPowerSourceUsesBatteryDischarging() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(isCharging: false, externalConnected: false)
        )

        XCTAssertEqual(state.powerSource, .battery)
        XCTAssertEqual(state.chargingMode, .discharging)
    }

    @MainActor
    func testDisconnectedPowerSourceIgnoresStaleChargingFlag() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(isCharging: true, externalConnected: false)
        )

        XCTAssertEqual(state.powerSource, .battery)
        XCTAssertEqual(state.chargingMode, .discharging)
    }

    @MainActor
    func testExternalConnectedChargingUsesACAdapterCharging() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(isCharging: true, externalConnected: true)
        )

        XCTAssertEqual(state.powerSource, .acAdapter)
        XCTAssertEqual(state.chargingMode, .charging)
    }

    @MainActor
    func testExternalConnectedNotChargingUsesPluggedIn() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(isCharging: false, externalConnected: true)
        )

        XCTAssertEqual(state.powerSource, .acAdapter)
        XCTAssertEqual(state.chargingMode, .pluggedIn)
    }
}
