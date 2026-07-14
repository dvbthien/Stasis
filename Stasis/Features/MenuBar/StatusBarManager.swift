import AppKit
import Defaults
import SwiftUI

/// Owns the `NSStatusItem` icon and keeps it in sync with battery state.
///
/// This is AppKit, not a SwiftUI `View` — it doesn't get automatic
/// re-invocation from `@Observable` the way a `body` does, so it still
/// needs the manual `withObservationTracking` + re-register dance. What
/// changed versus the `MenuViewModel` version is *what* it observes: the
/// real Models (`BatteryService`, `LowPowerModeMonitor`) directly, with no
/// ViewModel proxy in between.
@MainActor
class StatusBarManager {
    private let statusItem: NSStatusItem
    private let batteryService: BatteryService
    private let lowPowerModeMonitor: LowPowerModeMonitor

    private var locationObservation: Defaults.Observation?
    private var showStateObservation: Defaults.Observation?
    private var lastRenderedState: StatusIconState?

    init(batteryService: BatteryService, lowPowerModeMonitor: LowPowerModeMonitor) {
        self.batteryService = batteryService
        self.lowPowerModeMonitor = lowPowerModeMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = ""
        }

        setupDefaultsObservations()
        startMetricsObservation()
        updateStatusIconIfNeeded()
    }

    func setMenu(_ menu: NSMenu) {
        statusItem.menu = menu
    }

    /// Checks the icon inputs whenever observed state changes, but only
    /// re-renders when the renderer's actual input snapshot changed.
    private func startMetricsObservation() {
        withObservationTracking {
            _ = batteryService.metrics
            _ = batteryService.adapterMetrics
            _ = lowPowerModeMonitor.isEnabled
            _ = ChargingDaemonManager.shared.daemonSettingsState?.settings.useHardwarePercentage
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusIconIfNeeded()
                self.startMetricsObservation()
            }
        }
    }

    private func setupDefaultsObservations() {
        locationObservation = Defaults.observe(.batteryPercentageDisplayLocation) { [weak self] _ in
            self?.updateStatusIconIfNeeded()
        }
        showStateObservation = Defaults.observe(.showBatteryStateInStatusIcon) { [weak self] _ in
            self?.updateStatusIconIfNeeded()
        }
    }

    private func updateStatusIconIfNeeded() {
        let state = makeStatusIconState()
        guard state != lastRenderedState else { return }
        lastRenderedState = state
        renderStatusIcon(state)
    }

    private func makeStatusIconState() -> StatusIconState {
        StatusIconState(
            metrics: batteryService.metrics,
            adapter: batteryService.adapterMetrics,
            isLowPower: lowPowerModeMonitor.isEnabled,
            useHardwarePercentage:
                ChargingDaemonManager.shared.daemonSettingsState?.settings.useHardwarePercentage
                ?? Defaults[.useHardwarePercentage],
            displayLocation: Defaults[.batteryPercentageDisplayLocation],
            showState: Defaults[.showBatteryStateInStatusIcon]
        )
    }

    private func renderStatusIcon(_ state: StatusIconState) {
        guard let button = statusItem.button else { return }
        let batteryImage = BatteryRenderer.render(
            level: state.level,
            chargingMode: state.chargingMode,
            isLowPower: state.isLowPower,
            displayLocation: state.displayLocation,
            showState: state.showState
        )

        button.image = batteryImage
        button.imagePosition = state.displayLocation == .nextToIcon ? .imageLeft : .imageOnly
    }
}
