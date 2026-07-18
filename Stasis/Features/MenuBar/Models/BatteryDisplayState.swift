import Foundation

struct BatteryDisplayState: Equatable {
    let powerSource: PowerSource
    let chargingMode: ChargingMode

    /// Derives the display state from IOKit power-source info only
    /// (ExternalConnected / IsCharging); SMC telemetry is not consulted.
    static func derive(metrics: BatteryMetrics) -> BatteryDisplayState {
        guard metrics.externalConnected else {
            return BatteryDisplayState(powerSource: .battery, chargingMode: .discharging)
        }

        return BatteryDisplayState(
            powerSource: .acAdapter,
            chargingMode: metrics.isCharging ? .charging : .pluggedIn
        )
    }
}
