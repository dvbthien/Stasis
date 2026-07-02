import Foundation

/// A pure, stateless snapshot of everything the menu needs to *display*
/// about battery/adapter metrics.
///
/// This is the "M" that SwiftUI views read directly (the MV pattern) —
/// there is no `@Observable` state here, no Task, no manual observation
/// loop. Each menu-item view builds one of these from `BatteryService`'s
/// already-`@Observable` `metrics`/`adapterMetrics`, right inside its own
/// `body`. Since `body` itself reads those `@Observable` properties,
/// SwiftUI re-invokes it automatically whenever they change — the same
/// thing `MenuViewModel`'s `Task` + `withObservationTracking` loop used to
/// do by hand, just built into SwiftUI already.
struct BatteryDisplayInfo {
    let displayPercentage: Int
    let percentageText: String

    let powerSource: PowerSource
    let powerSourceText: String

    let timeRemainingText: String

    let chargingMode: ChargingMode
    let batteryModeText: String

    let batteryTemperatureText: String
    let externalInputText: String
    let internalInputText: String
    let cycleCountText: String
    let batteryHealthText: String

    let isCharging: Bool
    let adapterConnected: Bool
    let batteryPower: Double
    let adapterPower: Double
    let systemPower: Double

    init(metrics: BatteryMetrics, adapter: AdapterMetrics, useHardwarePercentage: Bool) {
        displayPercentage = useHardwarePercentage ? metrics.hardwareBatteryPercentage : metrics.batteryPercentage
        percentageText = "\(displayPercentage)%"

        let displayState = BatteryDisplayState.derive(metrics: metrics, adapter: adapter)
        powerSource = displayState.powerSource
        chargingMode = displayState.chargingMode

        switch displayState.powerSource {
        case .battery:
            powerSourceText = String(localized: "Battery")
        case .acAdapter:
            powerSourceText = String(localized: "Power Adapter")
        case .both:
            powerSourceText = String(localized: "Battery & Power Adapter")
        }

        let formattedTime = Self.formatTimeRemaining(minutes: metrics.timeRemaining)
        if !formattedTime.isEmpty {
            timeRemainingText = formattedTime
        } else if displayState.powerSource == .acAdapter && !metrics.isCharging {
            timeRemainingText = String(localized: "Not Charging")
        } else {
            timeRemainingText = String(localized: "Calculating...")
        }

        switch displayState.chargingMode {
        case .charging:
                batteryModeText = String(localized: "Charging")
        case .pluggedIn:
                batteryModeText = String(localized: "Plugged In (Not Charging)")
        case .discharging:
            batteryModeText = String(localized: "Discharging")
        }

        batteryTemperatureText =
            "\(metrics.batteryTemperature.formatted(.number.precision(.fractionLength(1))))°C"

        let voltageFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        let currentFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        externalInputText =
            "\(adapter.adapterVoltage.formatted(voltageFormat))V @ \(adapter.adapterCurrent.formatted(currentFormat))A"
        internalInputText =
            "\(metrics.batteryVoltage.formatted(voltageFormat))V @ \(metrics.batteryCurrent.formatted(currentFormat))A"

        cycleCountText = "\(metrics.cycleCount)"
        batteryHealthText = "\(metrics.batteryHealth)%"

        isCharging = metrics.isCharging
        adapterConnected = adapter.adapterConnected
        batteryPower = metrics.batteryPower
        adapterPower = adapter.adapterPower
        systemPower = adapter.adapterPower - metrics.batteryPower
    }

    private static func formatTimeRemaining(minutes: Int) -> String {
        guard minutes >= 0 else { return "" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
