import Foundation
import Observation

/// Publishes a formatted "time since boot" string, ticking once a minute
/// while started.
///
/// Only runs while explicitly `start()`ed — `AppDelegate` starts it on
/// `menuWillOpen` and stops it on `menuDidClose`, exactly like the uptime
/// timer used to work inside `MenuViewModel`, so it doesn't keep ticking in
/// the background while nobody can see it.
@MainActor
@Observable
final class UptimeClock {
    private(set) var text: String = String(localized: "Unknown")

    private var tickTask: Task<Void, Never>?

    func start() {
        guard tickTask == nil else { return }
        refresh()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refresh()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func refresh() {
        guard let bootTimestamp = SystemService.bootTimestamp() else {
            text = String(localized: "Unknown")
            return
        }
        let elapsed = Duration.seconds(Date().timeIntervalSince(bootTimestamp))
        text = elapsed.formatted(
            .units(
                allowed: [.days, .hours, .minutes],
                width: .condensedAbbreviated,
                zeroValueUnits: .hide
            ))
    }
}
