import Foundation

public struct SMCFirmwareChargeLimitState: Codable, Equatable, Sendable {
    public let active: Bool
    public let lower: UInt32
    public let upper: UInt32
}

extension SMCBattery {
    public func getFirmwareChargeLimit() throws -> SMCFirmwareChargeLimitState {
        try requireMode(.firmware)

        let activation = try read(.firmwareActivation, expectedSize: 1)
        let upper = try read(.firmwareUpperLimit, expectedSize: 4).littleEndianUInt32
        let lower = try read(.firmwareLowerLimit, expectedSize: 4).littleEndianUInt32

        return SMCFirmwareChargeLimitState(
            active: activation[activation.startIndex] == 0x02,
            lower: lower,
            upper: upper
        )
    }

    @discardableResult
    public func ensureFirmwareChargeLimit(lower: Int, upper: Int) throws -> Bool {
        try requireMode(.firmware)
        guard lower >= 0, upper <= 100, lower < upper else {
            throw SMCBatteryError.invalidFirmwareLimits(lower: lower, upper: upper)
        }

        if upper == 100 {
            return try ensureFirmwareChargeLimitDisabled()
        }

        let current = try getFirmwareChargeLimit()
        guard !current.active || current.lower != lower || current.upper != upper else {
            return false
        }

        try transport.write(Data([0x00]), to: .firmwareActivation)
        try transport.write(Data(littleEndian: UInt32(upper)), to: .firmwareUpperLimit)
        try transport.write(Data(littleEndian: UInt32(lower)), to: .firmwareLowerLimit)
        try transport.write(Data([0x02]), to: .firmwareActivation)
        return true
    }

    @discardableResult
    public func ensureFirmwareChargeLimitDisabled() throws -> Bool {
        try requireMode(.firmware)
        let activation = try read(.firmwareActivation, expectedSize: 1)
        guard activation[activation.startIndex] != 0x00 else { return false }

        try transport.write(Data([0x00]), to: .firmwareActivation)
        return true
    }
}
