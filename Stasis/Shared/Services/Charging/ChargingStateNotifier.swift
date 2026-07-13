import Defaults
import UserNotifications
import os.log

struct ChargingNotificationTransition: Equatable {
    let charging: Bool
    let reason: String?
}

struct ChargingNotificationTransitionTracker {
    private var lastChargingState: Bool?

    mutating func process(snapshot: DaemonSnapshot) -> ChargingNotificationTransition? {
        guard snapshot.policy.managementEnabled,
            snapshot.adapter.physicallyConnected,
            let desiredCharging = snapshot.policy.desiredCharging
        else {
            lastChargingState = nil
            return nil
        }

        guard desiredCharging != lastChargingState else { return nil }
        lastChargingState = desiredCharging
        return ChargingNotificationTransition(
            charging: desiredCharging,
            reason: snapshot.policy.reason
        )
    }

    mutating func reset() {
        lastChargingState = nil
    }
}

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
    private var transitionTracker = ChargingNotificationTransitionTracker()
    private let logger = Logger.stasis("ChargingStateNotifier")

    /// Clears the de-duplication state, e.g. after the adapter is
    /// reconnected or management is re-enabled, so the next evaluation is
    /// free to notify again even if it lands on the same charging state as
    /// before the reset.
    func reset() {
        transitionTracker.reset()
    }

    /// Consumes daemon-owned policy state. Firmware mode leaves
    /// `desiredCharging` nil, so the app does not infer direct charging state
    /// from firmware-managed battery flow.
    func process(snapshot: DaemonSnapshot) {
        guard let transition = transitionTracker.process(snapshot: snapshot) else { return }
        notifyIfChanged(
            charging: transition.charging,
            reason: transition.reason
        )
    }

    private func notifyIfChanged(charging: Bool, reason: String?) {
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
