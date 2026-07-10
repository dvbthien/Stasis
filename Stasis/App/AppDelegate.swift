import AppKit
import Defaults
import IOKit
import Observation
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusBarManager: StatusBarManager!
    private var batteryService: BatteryService!
    private var chargingCoordinator: ChargingCoordinator!
    private var lowPowerModeMonitor: LowPowerModeMonitor!
    private var uptimeClock: UptimeClock!
    private var menuBuilder: MenuBuilder!
    private var settingsWindowController: SettingsWindowController!
    private var menu: NSMenu!
    private var settingsObservation: Task<Void, Never>?
    private var adapterObservation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Exit the app immediately if the device doesn't have a battery
        let batteryIOService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard batteryIOService != 0 else {
            NSApplication.shared.terminate(nil)
            return
        }
        IOObjectRelease(batteryIOService)

        Task {
            await setupServices()
            setupMenu()
            requestNotificationPermissions()
        }
    }

    private func setupServices() async {
        batteryService = BatteryService()
        await batteryService.loadCapabilities()
        chargingCoordinator = ChargingCoordinator(batteryService: batteryService)
        lowPowerModeMonitor = LowPowerModeMonitor()
        uptimeClock = UptimeClock()
        settingsWindowController = SettingsWindowController(
            capabilities: batteryService.deviceCapabilities)
        menuBuilder = MenuBuilder(
            batteryService: batteryService,
            chargingCoordinator: chargingCoordinator,
            uptimeClock: uptimeClock,
            settingsWindowController: settingsWindowController
        )
        statusBarManager = StatusBarManager(
            batteryService: batteryService,
            lowPowerModeMonitor: lowPowerModeMonitor
        )
    }

    private func setupMenu() {
        menu = menuBuilder.buildMenu()
        menu.delegate = self
        statusBarManager.setMenu(menu)
        observeMenuSettingsChanges()
    }

    private func observeMenuSettingsChanges() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .showPowerSource, .showTimeTillDischarge, .showBatteryCycleCount,
                    .showBatteryHealth, .showBatteryTemperature, .showUptime,
                    .showBatteryMode, .showInternalPower, .showExternalPower,
                    .showPowerDistribution, .manageCharging,
                ],
                initial: false
            ) {
                self?.rebuildMenu()
            }
        }

        adapterObservation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.rebuildMenu()
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        // `controlState` only changes on percentage/temperature/
                        // adapter-connection transitions — unlike `adapterMetrics`,
                        // it doesn't carry the jittery SMC voltage/current
                        // readings, so this doesn't rebuild the whole menu on
                        // every fast-poll tick.
                        _ = self.batteryService.controlState.adapterConnected
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func rebuildMenu() {
        menuBuilder.populateMenu(menu)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsWindowController.cancelPendingRestart()
        settingsObservation?.cancel()
        settingsObservation = nil
        adapterObservation?.cancel()
        adapterObservation = nil

        chargingCoordinator?.stop()
        batteryService?.stop()
        uptimeClock?.stop()
        ChargingDaemonManager.shared.disconnect()
    }

    func menuWillOpen(_ menu: NSMenu) {
        uptimeClock.start()
        batteryService.enableFastPolling()
    }

    func menuDidClose(_ menu: NSMenu) {
        uptimeClock.stop()
        batteryService.disableFastPolling()
    }
}
