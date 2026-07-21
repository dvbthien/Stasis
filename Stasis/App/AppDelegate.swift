import AppKit
import Defaults
import IOKit
import Observation
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusBarManager: StatusBarManager!
    private var batteryService: BatteryService!
    private var lowPowerModeMonitor: LowPowerModeMonitor!
    private var uptimeClock: UptimeClock!
    private var menuBuilder: MenuBuilder!
    private var menu: NSMenu!
    private var settingsObservation: Task<Void, Never>?
    private var adapterObservation: Task<Void, Never>?
    private var chargingNotificationObservation: Task<Void, Never>?
    private let chargingStateNotifier = ChargingStateNotifier()

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

        setupServices()
        setupMenu()
        requestNotificationPermissions()
    }

    private func setupServices() {
        batteryService = BatteryService()
        lowPowerModeMonitor = LowPowerModeMonitor()
        uptimeClock = UptimeClock()
        // The Settings scene observes deviceCapabilities on the service
        // directly, so daemon updates flow to it without a mirror copy.
        SettingsSceneController.shared.batteryService = batteryService
        if !Defaults[.hasCompletedOnboarding] {
            SettingsSceneController.shared.open()
        }
        menuBuilder = MenuBuilder(
            batteryService: batteryService,
            uptimeClock: uptimeClock
        )
        statusBarManager = StatusBarManager(
            batteryService: batteryService,
            lowPowerModeMonitor: lowPowerModeMonitor
        )
        observeDaemonChargingNotifications()
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
                    .showPowerDistribution,
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
                await self.nextChange {
                    // `controlState` only changes on percentage/temperature/
                    // adapter-connection transitions — unlike `adapterMetrics`,
                    // it doesn't carry the jittery SMC voltage/current
                    // readings, so this doesn't rebuild the whole menu on
                    // every fast-poll tick.
                    _ = self.batteryService.controlState.adapterConnected
                    _ = ChargingDaemonManager.shared.chargingManagementSettings
                }
            }
        }
    }

    /// Suspends until a value read inside `tracking` changes. An AsyncStream
    /// ends its iteration when the awaiting task is cancelled, so — unlike
    /// parking on a bare `withCheckedContinuation` — cancelling the
    /// observation task while it waits here doesn't leak a continuation.
    private func nextChange(in tracking: @escaping () -> Void) async {
        let changes = AsyncStream<Void> { continuation in
            withObservationTracking(tracking) {
                continuation.finish()
            }
        }
        for await _ in changes {}
    }

    private func rebuildMenu() {
        menuBuilder.populateMenu(menu)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    private func observeDaemonChargingNotifications() {
        chargingNotificationObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.nextChange {
                    if let snapshot = ChargingDaemonManager.shared.daemonSnapshot {
                        self.chargingStateNotifier.process(snapshot: snapshot)
                    }
                }
            }
        }
    }

    // Keep the menu-bar app alive when the Settings window (the only
    // window scene) closes — SwiftUI's default is to quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SettingsSceneController.shared.cancelPendingRestart()
        settingsObservation?.cancel()
        settingsObservation = nil
        adapterObservation?.cancel()
        adapterObservation = nil
        chargingNotificationObservation?.cancel()
        chargingNotificationObservation = nil

        batteryService?.stop()
        uptimeClock?.stop()
        ChargingDaemonManager.shared.disconnect()
    }

    func menuWillOpen(_ menu: NSMenu) {
        uptimeClock.start()
        batteryService.setFastTelemetryEnabled(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        uptimeClock.stop()
        batteryService.setFastTelemetryEnabled(false)
    }
}
