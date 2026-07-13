import Foundation
import SMCKit

public enum MagSafeLEDState: UInt8, Codable, Sendable {
    case reset = 0
    case off = 1
    case green = 3
    case orange = 4
    case blinkOrangeSlow = 6
    case blinkOrangeFast = 7
}

public enum SMCAdapterError: Error, Equatable, Sendable {
    case powerControlNotSupported
    case magSafeNotSupported
    case unknownLEDState(UInt8)
    case invalidDataLength(key: String, expected: Int, actual: Int)
}

public struct AdapterCapabilities: Codable, Equatable, Sendable {
    public let powerControl: Bool
    public let magSafeControl: Bool
}

/*
 * Adapter priority and disable values are ported from batt:
 * CH0I -> CH0J -> CHIE, with 0x01 for CH0I/CH0J and 0x08 for CHIE.
 */
public struct SMCAdapter: Sendable {
    public let capabilities: AdapterCapabilities

    private let transport: any SMCTransport
    private let powerKey: SMCControlKey?
    private let hasMagSafeLEDKey: Bool

    public static func probe() throws -> SMCAdapter {
        try probe(using: SMCKitTransport())
    }

    static func probe(using transport: any SMCTransport) throws -> SMCAdapter {
        let powerKey = try firstUsablePowerKey(using: transport)
        let hasMagSafeLEDKey = try SMCChargeControlProbe.isUsable(
            .magSafeLED,
            expectedSize: 1,
            using: transport
        )

        return SMCAdapter(
            capabilities: AdapterCapabilities(
                powerControl: powerKey != nil,
                magSafeControl: hasMagSafeLEDKey
            ),
            transport: transport,
            powerKey: powerKey,
            hasMagSafeLEDKey: hasMagSafeLEDKey
        )
    }

    private static func firstUsablePowerKey(
        using transport: any SMCTransport
    ) throws -> SMCControlKey? {
        for key in [
            SMCControlKey.adapterPrimary,
            .adapterSecondary,
            .tahoeAdapter,
        ] where try SMCChargeControlProbe.isUsable(key, expectedSize: 1, using: transport) {
            return key
        }
        return nil
    }

    private init(
        capabilities: AdapterCapabilities,
        transport: any SMCTransport,
        powerKey: SMCControlKey?,
        hasMagSafeLEDKey: Bool
    ) {
        self.capabilities = capabilities
        self.transport = transport
        self.powerKey = powerKey
        self.hasMagSafeLEDKey = hasMagSafeLEDKey
    }

    public static func getVoltage() throws -> Double {
        Double(try SMCKit.shared.read("VD0R") as Float)
    }

    public static func getCurrent() throws -> Double {
        Double(try SMCKit.shared.read("ID0R") as Float)
    }

    public func getPowerEnabled() throws -> Bool {
        guard let powerKey else { throw SMCAdapterError.powerControlNotSupported }
        let data = try read(powerKey, expectedSize: 1)
        return data[data.startIndex] == 0x00
    }

    public func setPowerEnabled(_ enabled: Bool) throws {
        guard let powerKey else { throw SMCAdapterError.powerControlNotSupported }
        let disabledValue: UInt8 = powerKey == .tahoeAdapter ? 0x08 : 0x01
        try transport.write(Data([enabled ? 0x00 : disabledValue]), to: powerKey)
    }

    @discardableResult
    public func ensurePowerEnabled(_ enabled: Bool) throws -> Bool {
        guard try getPowerEnabled() != enabled else { return false }
        try setPowerEnabled(enabled)
        return true
    }

    public func getMagSafeLEDState() throws -> MagSafeLEDState {
        guard hasMagSafeLEDKey else { throw SMCAdapterError.magSafeNotSupported }
        let data = try read(.magSafeLED, expectedSize: 1)
        let raw = data[data.startIndex]
        guard let state = MagSafeLEDState(rawValue: raw) else {
            throw SMCAdapterError.unknownLEDState(raw)
        }
        return state
    }

    public func setMagSafeLEDState(_ state: MagSafeLEDState) throws {
        guard hasMagSafeLEDKey else { throw SMCAdapterError.magSafeNotSupported }
        try transport.write(Data([state.rawValue]), to: .magSafeLED)
    }

    private func read(_ key: SMCControlKey, expectedSize: Int) throws -> Data {
        let data = try transport.read(key)
        guard data.count == expectedSize else {
            throw SMCAdapterError.invalidDataLength(
                key: key.rawValue,
                expected: expectedSize,
                actual: data.count
            )
        }
        return data
    }
}
