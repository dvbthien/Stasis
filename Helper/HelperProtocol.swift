import Foundation

@objc protocol HelperProtocol {
    func readBatteryMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void)
    func readAdapterMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void)
    /// Reads battery and adapter metrics in a single round trip. Preferred
    /// over calling `readBatteryMetrics` and `readAdapterMetrics` separately
    /// when both are needed (e.g. during fast polling), since it halves the
    /// number of XPC messages exchanged per poll cycle.
    func readAllMetrics(
        reply: @escaping @Sendable (Double, Double, Double, Double, Double, Double) -> Void)
    func getCapabilities(
        reply: @escaping @Sendable (Bool, Bool, Bool, Bool) -> Void)
}
