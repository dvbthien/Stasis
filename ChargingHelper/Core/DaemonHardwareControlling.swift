import Foundation

protocol DaemonHardwareControlling: Sendable {
    @discardableResult
    func setChargingEnabled(_ enabled: Bool) async throws -> Bool
    @discardableResult
    func setAdapterEnabled(_ enabled: Bool) async throws -> Bool
    @discardableResult
    func setMagSafeLED(rawValue: UInt8) async throws -> Bool
    @discardableResult
    func ensureFirmwareChargeLimit(lower: Int, upper: Int) async throws -> Bool
    @discardableResult
    func ensureFirmwareChargeLimitDisabled() async throws -> Bool
    func readHardwareState() async throws -> DaemonHardwareState
    func readTelemetry() async -> DaemonTelemetryReading
    func resetToDefaults() async
}

extension DaemonHardwareControlling {
    func ensureFirmwareChargeLimit(lower _: Int, upper _: Int) async throws -> Bool {
        throw DaemonErrorPayload(
            code: .unsupported,
            message: "Firmware charge-limit control is unavailable"
        )
    }

    func ensureFirmwareChargeLimitDisabled() async throws -> Bool {
        throw DaemonErrorPayload(
            code: .unsupported,
            message: "Firmware charge-limit control is unavailable"
        )
    }
}
