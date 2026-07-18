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
          .frame(minWidth: 760, minHeight: 560)
          .task {
            try? await Task.sleep(for: .seconds(2))
            capabilitiesWaitTimedOut = true
          }
      }
    }
    .background(SettingsWindowAdopter())
    .onAppear {
      // Covers open paths that bypass SettingsSceneController.open(),
      // such as the standard ⌘, shortcut.
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
