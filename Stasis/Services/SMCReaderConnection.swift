import Foundation
import os.log

/// Manages the XPC connection to the read-only SMC reader helper.
///
/// `Helper` is an XPC Service of type `Application` (see Helper/Info.plist),
/// which means launchd/xpcproxy spawns a fresh process on demand whenever a
/// connection is resumed, and tears it down once no connection references it.
/// Because of that lifecycle, this class intentionally does NOT implement its
/// own reconnect-with-backoff loop: calling `connect()` again while the old
/// `connection` instance hasn't finished invalidating yet briefly creates two
/// live connections to the same service, and the helper process ends up
/// fielding messages from both until the stale one is fully torn down. Over
/// thousands of poll cycles (fast polling runs every second while the menu is
/// open) that overlap adds up. Instead, `connection` is only ever set to nil
/// from `invalidationHandler` — the one place that is guaranteed to mean "this
/// connection object is fully dead" — and the next call to `getHelper()`
/// lazily spins up a brand new one. `interruptionHandler` does NOT touch
/// `connection`; the connection object itself is still valid after an
/// interruption (the remote process merely restarted), and NSXPCConnection
/// will automatically re-launch the service and resume working on the next
/// call. Tearing it down ourselves here would just race with that.
///
/// Owned exclusively by `SMCMetricsPoller`, which is also the only place that
/// decides when to call `disconnect()`. Nothing else should hold a reference
/// to this class — connection lifecycle and "is this still needed" logic
/// belong together in one place, not spread across callers.
@MainActor
final class SMCReaderConnection {
    private var connection: NSXPCConnection?
    private let serviceName: String
    private let logger = Logger.stasis("SMCReaderConnection")

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    /// Returns a remote proxy for the helper, lazily creating the connection
    /// if needed. `errorHandler` is invoked by NSXPCConnection if the specific
    /// call this proxy is used for fails; it is not stored beyond that call.
    func getHelper(errorHandler: @escaping @Sendable (Error) -> Void) -> HelperProtocol? {
        if connection == nil {
            connect()
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? HelperProtocol
    }

    private func connect() {
        logger.info("Setting up XPC connection to \(self.serviceName)")
        let newConnection = NSXPCConnection(serviceName: serviceName)
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: HelperProtocol.self
        )

        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.logger.error("XPC connection invalidated")
                self?.connection = nil
            }
        }

        newConnection.interruptionHandler = { [weak self] in
            // The XPC service process exited (e.g. crashed, or was reaped by
            // the system after a period of inactivity) but the connection
            // object is still usable. Do NOT invalidate or recreate it here:
            // NSXPCConnection will relaunch the service automatically the
            // next time it's used. Just log for visibility.
            self?.logger.warning("XPC connection interrupted; will auto-relaunch on next use")
        }

        newConnection.resume()
        connection = newConnection
        logger.info("XPC connection resumed")
    }

    /// Tears down the connection entirely. Safe to call even if there is no
    /// active connection. After this, the underlying XPC service process is
    /// free to exit, releasing whatever memory it had accumulated — call this
    /// whenever polling stops so the helper isn't kept alive needlessly.
    func disconnect() {
        guard connection != nil else { return }
        logger.info("Disconnecting XPC connection")
        connection?.invalidate()
        connection = nil
    }
}
