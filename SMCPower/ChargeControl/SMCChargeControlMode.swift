import Foundation

public enum SMCChargeControlMode: String, Codable, CaseIterable, Sendable {
    case unsupported
    case legacy
    case firmware
}

enum SMCChargeControlProbe {
    static func mode(using transport: any SMCTransport) throws -> SMCChargeControlMode {
        let hasFirmwareKeys =
            try isUsable(.firmwareActivation, expectedSize: 1, using: transport)
            && isUsable(.firmwareUpperLimit, expectedSize: 4, using: transport)
            && isUsable(.firmwareLowerLimit, expectedSize: 4, using: transport)

        if hasFirmwareKeys {
            return .firmware
        }

        let hasPairedLegacyKeys =
            try isUsable(.legacyChargingPrimary, expectedSize: 1, using: transport)
            && isUsable(.legacyChargingSecondary, expectedSize: 1, using: transport)
        let hasTahoeLegacyKey = try isUsable(
            .tahoeCharging,
            expectedSize: 4,
            using: transport
        )

        return hasPairedLegacyKeys || hasTahoeLegacyKey ? .legacy : .unsupported
    }

    static func isUsable(
        _ key: SMCControlKey,
        expectedSize: Int,
        using transport: any SMCTransport
    ) throws -> Bool {
        guard try transport.dataSize(for: key) == expectedSize else { return false }
        return try transport.read(key).count == expectedSize
    }
}
