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

        chargingMode = BatteryDisplayState.derive(metrics: metrics, adapter: adapter).chargingMode

        self.isLowPower = isLowPower
        self.displayLocation = displayLocation
        self.showState = showState
    }
}
