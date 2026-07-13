import Foundation

protocol DaemonHardwareControlling: Sendable {
    func setChargingEnabled(_ enabled: Bool) async throws
    func setAdapterEnabled(_ enabled: Bool) async throws
    func setMagSafeLED(rawValue: UInt8) async throws
    func readHardwareState() async throws -> DaemonHardwareState
    func resetToDefaults() async
}
