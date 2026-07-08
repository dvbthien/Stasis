import Foundation
import Observation

/// Publishes the system's Low Power Mode state.
///
/// A small, reusable system-level Model — not scoped to any one screen —
/// so both `StatusBarManager` (AppKit) and any SwiftUI menu view can
/// observe it directly, the same way they already observe `BatteryService`.
@MainActor
@Observable
final class LowPowerModeMonitor {
    private(set) var isEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    init() {
        Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .NSProcessInfoPowerStateDidChange,
                object: ProcessInfo.processInfo
            )
            for await _ in notifications {
                self?.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
