import SwiftUI

/// Root of the `Settings` scene. Waits for device capabilities (loaded
/// asynchronously at launch) before building the real Settings UI, and hands
/// the hosting NSWindow to `SettingsSceneController` so the app-level behaviors
/// (Dock icon, restart-on-close, background dragging) survive the migration
/// off the manual NSWindow controller.
struct SettingsRootView: View {
    private let controller = SettingsSceneController.shared

    /// Fallback so Settings never spins forever when the daemon is not
    /// installed or cannot connect: after this grace period the UI renders
    /// with whatever capabilities are available.
    @State private var capabilitiesWaitTimedOut = false

    var body: some View {
        Group {
            if let batteryService = controller.batteryService,
                batteryService.capabilitiesLoaded || capabilitiesWaitTimedOut
            {
                SettingsView(capabilities: batteryService.deviceCapabilities)
            } else {
                ProgressView()
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        capabilitiesWaitTimedOut = true
                    }
            }
        }
        .background(SettingsWindowAdopter())
        .modifier(HideWindowTitle())
        .toolbar {
            ToolbarItem {
                Color.clear
                    .frame(width: 20, height: 20)
            }
        }
        .onAppear {
            // Every open path (SettingsLink, ⌘,, reopening a still-live window)
            // routes through here, so this is also where a restart scheduled by
            // a previous close gets cancelled.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Hands the scene's NSWindow to SettingsSceneController as soon as the view is
/// attached to it.
private struct SettingsWindowAdopter: NSViewRepresentable {
    final class WindowGrabberView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                SettingsSceneController.shared.adopt(window: window)
            }
        }
    }

    func makeNSView(context: Context) -> WindowGrabberView {
        WindowGrabberView()
    }

    func updateNSView(_ nsView: WindowGrabberView, context: Context) {}
}

/// Keeps SwiftUI from re-asserting "Stasis Settings" into the window title on
/// tab switches or sidebar collapse — unlike the didUpdate observer in
/// SettingsSceneController, which only clears it a frame later and flickers.
/// On macOS 15+ the title toolbar item is removed outright; on macOS 14 an
/// empty title is set instead (`Text(verbatim:)` so no "" key leaks into the
/// localization catalog).
private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle(Text(verbatim: ""))
        }
    }
}
