import Foundation

/// Read-only Application XPC service used by the app for UI telemetry.
///
/// This surface intentionally exposes no capability probing and no SMC write
/// operation. Charging-control capabilities remain authoritative in the daemon.
@objc protocol SMCReaderHelperProtocol {
    func readAllMetrics(reply: @escaping @Sendable (Data?, String?) -> Void)
}
