import Foundation

/// Callback surface exported by Stasis for daemon-originated state changes.
@objc protocol ChargingDaemonClientProtocol {
    func stateDidChange(_ payload: Data)
    func settingsDidChange(_ payload: Data)
}
