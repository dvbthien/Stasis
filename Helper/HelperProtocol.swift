import Foundation

@objc protocol HelperProtocol {
    /// Reads battery and adapter metrics in a single XPC round trip.
    func readAllMetrics(
        reply: @escaping @Sendable (Double, Double, Double, Double, Double, Double) -> Void)
    func getCapabilities(
        reply: @escaping @Sendable (Bool, Bool, Bool, Bool) -> Void)
}
