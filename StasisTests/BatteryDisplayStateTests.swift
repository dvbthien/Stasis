import XCTest

@testable import Stasis

final class BatteryDisplayStateTests: XCTestCase {
    @MainActor
    func testDisconnectedAdapterUsesBatteryDespiteStaleSMCValues() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(
                isCharging: true,
                batteryPower: 8,
                externalConnected: true
            ),
            adapter: AdapterMetrics(
                adapterConnected: false,
                powerEnabled: true,
                adapterPower: 45
            )
        )

        XCTAssertEqual(state.powerSource, .battery)
        XCTAssertEqual(state.chargingMode, .discharging)
    }

    @MainActor
    func testConnectedAdapterWithoutSMCPowerUsesBattery() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(isCharging: false, externalConnected: true),
            adapter: AdapterMetrics(adapterConnected: true, powerEnabled: true)
        )

        XCTAssertEqual(state.powerSource, .battery)
        XCTAssertEqual(state.chargingMode, .discharging)
    }

    @MainActor
    func testConnectedAdapterChargingWithNonnegativeBatteryPowerUsesACAdapter() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(
                isCharging: true,
                batteryPower: 8,
                externalConnected: true
            ),
            adapter: AdapterMetrics(
                adapterConnected: true,
                powerEnabled: true,
                adapterPower: 45
            )
        )

        XCTAssertEqual(state.powerSource, .acAdapter)
        XCTAssertEqual(state.chargingMode, .charging)
    }

    @MainActor
    func testConnectedAdapterNotChargingWithNonnegativeBatteryPowerUsesPluggedIn() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(
                isCharging: false,
                batteryPower: 0,
                externalConnected: true
            ),
            adapter: AdapterMetrics(
                adapterConnected: true,
                powerEnabled: true,
                adapterPower: 45
            )
        )

        XCTAssertEqual(state.powerSource, .acAdapter)
        XCTAssertEqual(state.chargingMode, .pluggedIn)
    }

    @MainActor
    func testConnectedAdapterWhileBatterySuppliesPowerUsesBoth() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(
                isCharging: false,
                batteryPower: -8,
                externalConnected: true
            ),
            adapter: AdapterMetrics(
                adapterConnected: true,
                powerEnabled: true,
                adapterPower: 45
            )
        )

        XCTAssertEqual(state.powerSource, .both)
        XCTAssertEqual(state.chargingMode, .discharging)
    }

    @MainActor
    func testAuxiliaryFlagsDoNotOverrideMeasuredPowerSource() {
        let state = BatteryDisplayState.derive(
            metrics: BatteryMetrics(
                isCharging: false,
                batteryPower: 0,
                externalConnected: false
            ),
            adapter: AdapterMetrics(
                adapterConnected: true,
                powerEnabled: false,
                adapterPower: 45
            )
        )

        XCTAssertEqual(state.powerSource, .acAdapter)
        XCTAssertEqual(state.chargingMode, .pluggedIn)
    }
}
