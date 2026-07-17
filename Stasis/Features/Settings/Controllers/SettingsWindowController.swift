import AppKit
import Defaults
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let sidebarToggleItemIdentifier = NSToolbarItem.Identifier("SidebarToggle")

    private let capabilities: DeviceCapabilities
    private let sidebarState = SettingsSidebarState()
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
        let settingsView = SettingsView(capabilities: capabilities, sidebarState: sidebarState)
        let hostingController = NSHostingController(rootView: settingsView)

        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = ""
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.styleMask.insert(.fullSizeContentView)
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.isMovableByWindowBackground = true
        settingsWindow.toolbarStyle = .unifiedCompact
        settingsWindow.toolbar = makeToolbar()
        settingsWindow.center()
        NSApp.setActivationPolicy(.regular)
        settingsWindow.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self

        return settingsWindow
    }

    // Build a plain AppKit toolbar with a sidebar-toggle button. SwiftUI's
    // `.toolbar` modifier content never reaches this manually created
    // NSWindow, so the toggle is implemented purely in AppKit and drives
    // the shared sidebar state that SettingsView's NavigationSplitView reads.
    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        return toolbar
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.sidebarToggleItemIdentifier else { return nil }

        let button = NSButton(
            image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")!,
            target: self,
            action: #selector(toggleSidebar)
        )
        button.isBordered = false
        button.bezelStyle = .texturedRounded

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = button
        item.label = ""
        item.paletteLabel = "Toggle Sidebar"
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarToggleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarToggleItemIdentifier]
    }

    @objc private func toggleSidebar() {
        sidebarState.toggle()
    }

    // Release the hosted Settings UI and optionally schedule an app restart.
    private func handleWindowWillClose() {
        NSApp.setActivationPolicy(.accessory)
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
