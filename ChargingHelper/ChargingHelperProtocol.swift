import Foundation

@objc protocol ChargingHelperProtocol {
  func checkHealth(reply: @escaping @Sendable (Bool, String?) -> Void)
  func manageBatteryCharging(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void)
  func manageExternalPower(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void)
  func manageMagsafeLED(target: UInt8, reply: @escaping @Sendable (Bool, String?) -> Void)
}
