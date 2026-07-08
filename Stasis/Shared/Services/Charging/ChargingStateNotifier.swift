import Defaults
import UserNotifications
import os.log

/// Sends the "Charging Resumed" / "Charging Paused" user notification
/// whenever the charging state actually changes, and tracks the last
/// notified state so repeated evaluations with the same outcome don't spam
/// duplicate notifications.
///
/// Pulled out of `ChargingCoordinator` so the notification de-duplication state
/// (`lastNotifiedChargingState`) and delivery logic live next to each
/// other, separate from charging policy itself.
@MainActor
final class ChargingStateNotifier {
    private var lastNotifiedChargingState: Bool?
    private let logger = Logger.stasis("ChargingStateNotifier")

    /// Clears the de-duplication state, e.g. after the adapter is
    /// reconnected or management is re-enabled, so the next evaluation is
    /// free to notify again even if it lands on the same charging state as
    /// before the reset.
    func reset() {
        lastNotifiedChargingState = nil
    }

    func notifyIfChanged(charging: Bool, reason: String?) {
        guard charging != lastNotifiedChargingState else { return }
        lastNotifiedChargingState = charging

        guard !Defaults[.disableNotifications],
            Defaults[.showChargingStatusChangedNotification]
        else { return }

        let content = UNMutableNotificationContent()
        content.title = charging ? String(localized: "Charging Resumed") : String(localized: "Charging Paused")
        if let reason {
            content.body = reason
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "chargingStateChanged",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to deliver notification: \(error)")
            }
        }
    }
}
