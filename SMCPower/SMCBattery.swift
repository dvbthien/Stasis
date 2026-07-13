import Foundation
import SMCKit

public enum SMCBatteryError: Error, Equatable, Sendable {
    case unsupportedCapability
    case wrongChargeControlMode(required: SMCChargeControlMode, actual: SMCChargeControlMode)
    case invalidDataLength(key: String, expected: Int, actual: Int)
    case invalidFirmwareLimits(lower: Int, upper: Int)
}

public struct BatteryCapabilities: Codable, Equatable, Sendable {
    public let chargeControlMode: SMCChargeControlMode
    public let inhibitChargeControl: Bool
    public let firmwareChargeLimitControl: Bool
}

private enum LegacyChargingBackend: Sendable {
    case pairedKeys
    case tahoeKey
}

/*
 * Charge-control behavior is ported from batt's macOS 27 support branch.
 * Mode selection is based only on validated SMC key sizes; firmware keys take
 * precedence when both firmware and legacy key families are exposed.
 */
public struct SMCBattery: Sendable {
    public let capabilities: BatteryCapabilities

    let transport: any SMCTransport
    private let legacyBackend: LegacyChargingBackend?

    public static func probe() throws -> SMCBattery {
        try probe(using: SMCKitTransport())
    }

    static func probe(using transport: any SMCTransport) throws -> SMCBattery {
        let mode = try SMCChargeControlProbe.mode(using: transport)
        let backend: LegacyChargingBackend?
        if mode == .legacy {
            let hasPairedLegacyKeys =
                try SMCChargeControlProbe.isUsable(
                    .legacyChargingPrimary,
                    expectedSize: 1,
                    using: transport
                )
                && SMCChargeControlProbe.isUsable(
                    .legacyChargingSecondary,
                    expectedSize: 1,
                    using: transport
                )
            backend = hasPairedLegacyKeys ? .pairedKeys : .tahoeKey
        } else {
            backend = nil
        }

        return SMCBattery(
            capabilities: BatteryCapabilities(
                chargeControlMode: mode,
                inhibitChargeControl: mode == .legacy,
                firmwareChargeLimitControl: mode == .firmware
            ),
            transport: transport,
            legacyBackend: backend
        )
    }

    private init(
        capabilities: BatteryCapabilities,
        transport: any SMCTransport,
        legacyBackend: LegacyChargingBackend?
    ) {
        self.capabilities = capabilities
        self.transport = transport
        self.legacyBackend = legacyBackend
    }

    public static func getVoltage() throws -> Double {
        Double(try SMCKit.shared.read("B0AV") as UInt16) / 1000.0
    }

    public static func getCurrent() throws -> Double {
        Double(try SMCKit.shared.read("B0AC") as Int16) / 1000.0
    }

    public func getChargingInhibited() throws -> Bool {
        try !getChargingEnabled()
    }

    public func setChargingInhibited(_ inhibited: Bool) throws {
        try setChargingEnabled(!inhibited)
    }

    public func getChargingEnabled() throws -> Bool {
        try requireMode(.legacy)

        switch legacyBackend {
        case .pairedKeys:
            return try read(.legacyChargingPrimary, expectedSize: 1) == Data([0x00])
        case .tahoeKey:
            return try read(.tahoeCharging, expectedSize: 4) == Data([0x00, 0x00, 0x00, 0x00])
        case nil:
            throw SMCBatteryError.unsupportedCapability
        }
    }

    public func setChargingEnabled(_ enabled: Bool) throws {
        try requireMode(.legacy)

        switch legacyBackend {
        case .pairedKeys:
            let value = Data([enabled ? 0x00 : 0x02])
            try transport.write(value, to: .legacyChargingPrimary)
            try transport.write(value, to: .legacyChargingSecondary)
        case .tahoeKey:
            try transport.write(
                Data([enabled ? 0x00 : 0x01, 0x00, 0x00, 0x00]),
                to: .tahoeCharging
            )
        case nil:
            throw SMCBatteryError.unsupportedCapability
        }
    }

    func requireMode(_ required: SMCChargeControlMode) throws {
        let actual = capabilities.chargeControlMode
        guard actual == required else {
            throw SMCBatteryError.wrongChargeControlMode(required: required, actual: actual)
        }
    }

    func read(_ key: SMCControlKey, expectedSize: Int) throws -> Data {
        let data = try transport.read(key)
        guard data.count == expectedSize else {
            throw SMCBatteryError.invalidDataLength(
                key: key.rawValue,
                expected: expectedSize,
                actual: data.count
            )
        }
        return data
    }
}
