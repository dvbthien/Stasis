import Defaults
import SwiftUI

/// Reads `BatteryService.metrics`/`.adapterMetrics` and the
/// `useHardwarePercentage` setting directly, rather than a ViewModel.
struct BatteryMainInfoView: View {
    let batteryService: BatteryService
    @Default(.useHardwarePercentage) private var useHardwarePercentage

    var body: some View {
        let info = BatteryDisplayInfo(
            metrics: batteryService.metrics,
            adapter: batteryService.adapterMetrics,
            useHardwarePercentage: useHardwarePercentage
        )
        BatteryMainInfo(label: String(localized: "Battery"), value: info.percentageText)
    }
}

struct BatteryAdditionalInfoObserverView: View {
    let label: String
    let batteryService: BatteryService
    let keyPath: KeyPath<BatteryDisplayInfo, String>
    @Default(.useHardwarePercentage) private var useHardwarePercentage

    var body: some View {
        let info = BatteryDisplayInfo(
            metrics: batteryService.metrics,
            adapter: batteryService.adapterMetrics,
            useHardwarePercentage: useHardwarePercentage
        )
        BatteryAdditionalInfo(label: label, value: info[keyPath: keyPath])
    }
}

struct UptimeInfoView: View {
    let uptimeClock: UptimeClock

    var body: some View {
        BatteryAdditionalInfo(label: String(localized: "Uptime"), value: uptimeClock.text)
    }
}

struct PowerSankeyViewWrapper: View {
    let batteryService: BatteryService
    @Default(.useHardwarePercentage) private var useHardwarePercentage

    var body: some View {
        let info = BatteryDisplayInfo(
            metrics: batteryService.metrics,
            adapter: batteryService.adapterMetrics,
            useHardwarePercentage: useHardwarePercentage
        )
        PowerSankeyView(
            powerSource: info.powerSource,
            isCharging: info.isCharging,
            batteryPower: info.batteryPower,
            adapterPower: info.adapterPower,
            systemPower: info.systemPower
        )
    }
}
