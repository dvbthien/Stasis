import AppKit
import Defaults
import SwiftUI
import smc_power

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let capabilities: DeviceCapabilities
    private var pendingRestart: Task<Void, Never>?

    // Store device capabilities so every new Settings window gets the same hardware context.
    init(capabilities: DeviceCapabilities) {
        self.capabilities = capabilities
        super.init(window: nil)
    }

    // This controller is code-only and should not be loaded from a storyboard or nib.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Reuse the existing Settings window or create one, then bring it to the front.
    func showSettings() {
        cancelPendingRestart()

        if window == nil {
            window = makeSettingsWindow()
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Cancel a restart that was scheduled after closing Settings.
    func cancelPendingRestart() {
        pendingRestart?.cancel()
        pendingRestart = nil
    }

    // Handle AppKit's close callback and run cleanup on the main actor.
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
            closingWindow === window
        else { return }
        
        handleWindowWillClose()
    }

    // Build the AppKit window that hosts the SwiftUI Settings view.
    private func makeSettingsWindow() -> NSWindow {
        let settingsView = SettingsView(capabilities: capabilities)
        let hostingController = NSHostingController(rootView: settingsView)

        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = ""
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.styleMask.insert(.fullSizeContentView)
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.isMovableByWindowBackground = true
        settingsWindow.center()
        settingsWindow.setFrameAutosaveName("SettingsWindow")
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self

        return settingsWindow
    }

    // Release the hosted Settings UI and optionally schedule an app restart.
    private func handleWindowWillClose() {
        window?.contentViewController = nil
        window = nil

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
