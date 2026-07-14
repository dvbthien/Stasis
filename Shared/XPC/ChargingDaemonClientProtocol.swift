import Foundation

/// Callback surface exported by Stasis for daemon-originated state changes.
@objc protocol ChargingDaemonClientProtocol {
    nonisolated func stateDidChange(_ payload: Data)
}
