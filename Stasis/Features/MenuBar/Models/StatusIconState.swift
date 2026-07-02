import Defaults
import Foundation

struct StatusIconState: Equatable {
    let level: Int
    let chargingMode: ChargingMode
    let isLowPower: Bool
    let displayLocation: PercentageDisplayLocation
    let showState: Bool

    init(
        metrics: BatteryMetrics,
        adapter: AdapterMetrics,
        isLowPower: Bool,
        useHardwarePercentage: Bool,
        displayLocation: PercentageDisplayLocation,
        showState: Bool
    ) {
        level = useHardwarePercentage
            ? metrics.hardwareBatteryPercentage
            : metrics.batteryPercentage

        let powerSource = Self.derivePowerSource(battery: metrics, adapter: adapter)
        if powerSource == .acAdapter {
            chargingMode = metrics.isCharging ? .charging : .pluggedIn
        } else {
            chargingMode = .discharging
        }

        self.isLowPower = isLowPower
        self.displayLocation = displayLocation
        self.showState = showState
    }

    private static func derivePowerSource(battery: BatteryMetrics, adapter: AdapterMetrics) -> PowerSource {
        guard adapter.adapterConnected else { return .battery }

        if adapter.adapterPower == 0 {
            return .battery
        } else if battery.batteryPower >= 0 {
            return .acAdapter
        } else {
            return .both
        }
    }
}
