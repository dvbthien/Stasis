import Foundation

struct BatteryDisplayState: Equatable {
    let powerSource: PowerSource
    let chargingMode: ChargingMode

    static func derive(metrics: BatteryMetrics, adapter: AdapterMetrics) -> BatteryDisplayState {
        let powerSource = derivePowerSource(metrics: metrics, adapter: adapter)
        let chargingMode: ChargingMode =
            if powerSource == .acAdapter {
                metrics.isCharging ? .charging : .pluggedIn
            } else {
                .discharging
            }

        return BatteryDisplayState(powerSource: powerSource, chargingMode: chargingMode)
    }

    private static func derivePowerSource(metrics: BatteryMetrics, adapter: AdapterMetrics) -> PowerSource {
        guard adapter.adapterConnected else { return .battery }

        if adapter.adapterPower == 0 {
            return .battery
        } else if metrics.batteryPower >= 0 {
            return .acAdapter
        } else {
            return .both
        }
    }
}
