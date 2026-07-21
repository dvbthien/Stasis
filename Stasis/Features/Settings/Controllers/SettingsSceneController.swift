import AppKit
import Defaults
import SwiftUI

/// App-level behavior for the SwiftUI `Settings` scene: shows the Dock icon
/// only while Settings is open, optionally restarts the app after the window
/// closes, and keeps the window chrome (hidden title, compact toolbar) from
/// being re-asserted by SwiftUI, which the Settings scene does on layout
/// changes such as collapsing the sidebar.
@MainActor
@Observable
final class SettingsSceneController {
    static let shared = SettingsSceneController()

    /// Set once during app startup; the Settings scene shows its content only
    /// once this is available, and reads `deviceCapabilities` from it directly
    /// so SwiftUI observation tracks daemon updates without a mirror copy.
    var batteryService: BatteryService?

    @ObservationIgnored private var pendingRestart: Task<Void, Never>?
    @ObservationIgnored private var windowObservers: [NSObjectProtocol] = []
    @ObservationIgnored private weak var settingsWindow: NSWindow?

    private init() {}

    private func observe(_ window: NSWindow) {
        windowObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window,
                        self.settingsWindow === window
                    else { return }
                    self.handleWindowWillClose()
                }
            },
            // The Settings scene re-asserts its "<App> Settings" title on
            // toolbar/layout updates (e.g. collapsing the sidebar), so
            // re-hide it whenever the window updates with a visible title.
            
            // Legacy code doesn't delete
//            NotificationCenter.default.addObserver(
//                forName: NSWindow.didUpdateNotification,
//                object: window,
//                queue: .main
//            ) { [weak self, weak window] _ in
//                MainActor.assumeIsolated {
//                    guard let self, let window,
//                        self.settingsWindow === window,
//                        window.titleVisibility != .hidden
//                            || !window.title.isEmpty
//                    else { return }
//                    self.applyChrome(to: window)
//                }
//            },
        ]
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }

    // Open (or focus) the Settings window from AppKit code.
    func open() {
        cancelPendingRestart()
        NSApp.setActivationPolicy(.regular)

        // isVisible is false while miniaturized, so check both.
        if let settingsWindow,
            settingsWindow.isVisible || settingsWindow.isMiniaturized
        {
            if settingsWindow.isMiniaturized {
                settingsWindow.deminiaturize(nil)
            }
            settingsWindow.makeKeyAndOrderFront(nil)
        } else if !openViaSettingsMenuItem() {
            // Last resort if the app menu has no Settings item: a hand-built
            // EnvironmentValues. Works on current macOS but is not a
            // supported pattern.
            EnvironmentValues().openSettings()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    /// Triggers the standard "Settings…" item SwiftUI puts in the app menu —
    /// the same code path as pressing ⌘, — so the scene opens without relying
    /// on a hand-built `EnvironmentValues`. Matches by key equivalent, which
    /// survives localization of the item's title.
    private func openViaSettingsMenuItem() -> Bool {
        guard
            let appMenu = NSApp.mainMenu?.items.first?.submenu,
            let item = appMenu.items.first(where: {
                $0.keyEquivalent == ","
                    && $0.keyEquivalentModifierMask == .command
            }),
            let action = item.action
        else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    // Called by the scene content once it knows its hosting window.
    func adopt(window: NSWindow) {
        guard window !== settingsWindow else { return }
        removeWindowObservers()
        settingsWindow = window
        window.isRestorable = false
        applyChrome(to: window)
        observe(window)

        // The scene may finish creating its window asynchronously, after
        // open() has already run its own order-front logic (or skipped it
        // because the window didn't exist yet), so make sure it always ends
        // up frontmost here too.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyChrome(to window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified

    }

    // Cancel a restart that was scheduled after closing Settings.
    func cancelPendingRestart() {
        pendingRestart?.cancel()
        pendingRestart = nil
    }

    private func handleWindowWillClose() {
        removeWindowObservers()
        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)

        guard Defaults[.restartOnClose] else { return }
        scheduleRestart()
    }

    // Defer restart briefly so normal app termination can cancel it first.
    private func scheduleRestart() {
        pendingRestart = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            self?.launchReplacementApp()
            NSApp.terminate(nil)
        }
    }

    // Launch a replacement app process before terminating the current one.
    private func launchReplacementApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 0.5; /usr/bin/open \"$1\"",
            "relaunch-stasis",
            Bundle.main.bundleURL.path,
        ]
        try? task.run()
    }
}
