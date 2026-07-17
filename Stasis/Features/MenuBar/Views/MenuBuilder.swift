import AppKit
import Defaults
import SwiftUI

/// Builds the status-item's `NSMenu` content out of small SwiftUI views,
/// each hosted via `NSHostingView`.
///
/// Each of those views reads app telemetry or daemon-owned state
/// directly and computes its own `BatteryDisplayInfo` inside `body` — the
/// MV pattern. Because `body` reads `@Observable` properties
/// (`batteryService.metrics`, `.adapterMetrics`), SwiftUI re-invokes it
/// automatically whenever they change; no ViewModel or manual observation
/// loop is needed to keep these items live.
@MainActor
class MenuBuilder {
    private let batteryService: BatteryService
    private let chargingControls = ChargingTemporaryControlsModel()
    private let uptimeClock: UptimeClock
    private let settingsWindowController: SettingsWindowController

    init(
        batteryService: BatteryService,
        uptimeClock: UptimeClock,
        settingsWindowController: SettingsWindowController
    ) {
        self.batteryService = batteryService
        self.uptimeClock = uptimeClock
        self.settingsWindowController = settingsWindowController
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Stasis")
        populateMenu(menu)
        return menu
    }

    func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let mainInfoItem = createMenuItem(
            view: BatteryMainInfoView(batteryService: batteryService)
        )
        menu.addItem(mainInfoItem)

        let sections: [[NSMenuItem]] = [
            buildInfoSection(),
            buildPowerMetricsSection(),
            buildVisualizationSection(),
            buildHardwareSection(),
        ]

        for section in sections where !section.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for item in section {
                menu.addItem(item)
            }
        }

        if ChargingDaemonManager.shared.chargingManagementSettings?.isEnabled == true
            && batteryService.adapterMetrics.adapterConnected
        {
            // Unknown capabilities (daemon still connecting) fall back to
            // showing every command, mirroring the daemon-side permissive
            // default for older daemons.
            let capabilities = ChargingDaemonManager.shared.capabilities
            var temporaryControlItems: [NSMenuItem] = []
            if capabilities?.chargeLimitOverrideControl ?? true {
                temporaryControlItems.append(
                    createMenuItem(view: ChargeLimitOverrideToggleView(controls: chargingControls)))
            }
            if capabilities?.forceDischargeControl ?? true {
                temporaryControlItems.append(
                    createMenuItem(view: ForceDischargeToggleView(controls: chargingControls)))
            }
            if !temporaryControlItems.isEmpty {
                menu.addItem(NSMenuItem.separator())
                temporaryControlItems.forEach(menu.addItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func buildInfoSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showPowerSource] {
            items.append(
                createInfoItem(label: String(localized: "Power Source"), keyPath: \.powerSourceText))
        }
        if Defaults[.showTimeTillDischarge] {
            items.append(
                createInfoItem(label: String(localized: "Time Remaining"), keyPath: \.timeRemainingText))
        }
        if Defaults[.showUptime] {
            items.append(createMenuItem(view: UptimeInfoView(uptimeClock: uptimeClock)))
        }
        if Defaults[.showBatteryMode] {
            items.append(
                createInfoItem(label: String(localized: "Battery Mode"), keyPath: \.batteryModeText))
        }

        return items
    }

    private func buildPowerMetricsSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showInternalPower] {
            items.append(createInfoItem(label: String(localized: "Battery"), keyPath: \.internalInputText))
        }
        if Defaults[.showExternalPower] {
            items.append(createInfoItem(label: String(localized: "Adapter"), keyPath: \.externalInputText))
        }

        return items
    }

    private func buildVisualizationSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showPowerDistribution] {
            items.append(createMenuItem(view: PowerSankeyViewWrapper(batteryService: batteryService)))
        }

        return items
    }

    private func buildHardwareSection() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if Defaults[.showBatteryCycleCount] {
            items.append(createInfoItem(label: String(localized: "Cycle Count"), keyPath: \.cycleCountText))
        }
        if Defaults[.showBatteryHealth] {
            items.append(
                createInfoItem(label: String(localized: "Battery Health"), keyPath: \.batteryHealthText))
        }
        if Defaults[.showBatteryTemperature] {
            items.append(
                createInfoItem(
                    label: String(localized: "Battery Temperature"), keyPath: \.batteryTemperatureText))
        }

        return items
    }

    private func createInfoItem(
        label: String,
        keyPath: KeyPath<BatteryDisplayInfo, String>
    ) -> NSMenuItem {
        createMenuItem(
            view: BatteryAdditionalInfoObserverView(
                label: label,
                batteryService: batteryService,
                keyPath: keyPath
            )
        )
    }

    private static let menuWidth: CGFloat = 300

    private func createMenuItem<V: View>(view: V) -> NSMenuItem {
        let hostingView = NSHostingView(rootView: view)
        let height = hostingView.fittingSize.height
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.menuWidth, height: height)

        let menuItem = NSMenuItem()
        menuItem.view = hostingView

        return menuItem
    }

    @objc private func handleSettings() {
        settingsWindowController.showSettings()
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
