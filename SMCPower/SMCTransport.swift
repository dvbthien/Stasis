import Foundation
import SMCKit

enum SMCControlKey: String, CaseIterable, Sendable {
    case legacyChargingPrimary = "CH0B"
    case legacyChargingSecondary = "CH0C"
    case tahoeCharging = "CHTE"

    case firmwareActivation = "bfF0"
    case firmwareUpperLimit = "bfD0"
    case firmwareLowerLimit = "bfE0"

    case adapterPrimary = "CH0I"
    case adapterSecondary = "CH0J"
    case tahoeAdapter = "CHIE"
    case magSafeLED = "ACLC"

    var code: FourCharCode {
        switch self {
        case .legacyChargingPrimary: "CH0B"
        case .legacyChargingSecondary: "CH0C"
        case .tahoeCharging: "CHTE"
        case .firmwareActivation: "bfF0"
        case .firmwareUpperLimit: "bfD0"
        case .firmwareLowerLimit: "bfE0"
        case .adapterPrimary: "CH0I"
        case .adapterSecondary: "CH0J"
        case .tahoeAdapter: "CHIE"
        case .magSafeLED: "ACLC"
        }
    }
}

enum SMCTransportError: Error, Equatable, Sendable {
    case keyNotFound(String)
    case invalidDataSize(key: String, expected: Int, actual: Int)
    case unsupportedWriteSize(key: String, size: Int)
}

protocol SMCTransport: Sendable {
    func dataSize(for key: SMCControlKey) throws -> Int?
    func read(_ key: SMCControlKey) throws -> Data
    func write(_ data: Data, to key: SMCControlKey) throws
}

struct SMCKitTransport: SMCTransport {
    func dataSize(for key: SMCControlKey) throws -> Int? {
        guard try SMCKit.shared.isKeyFound(key.code) else { return nil }
        return Int(try SMCKit.shared.getKeyInformation(key.code).size)
    }

    func read(_ key: SMCControlKey) throws -> Data {
        try SMCKit.shared.readData(key.code)
    }

    func write(_ data: Data, to key: SMCControlKey) throws {
        guard let expectedSize = try dataSize(for: key) else {
            throw SMCTransportError.keyNotFound(key.rawValue)
        }
        guard data.count == expectedSize else {
            throw SMCTransportError.invalidDataSize(
                key: key.rawValue,
                expected: expectedSize,
                actual: data.count
            )
        }

        if key == .tahoeAdapter {
            try SMCKit.shared.writeData(key.code, data)
            return
        }

        switch data.count {
        case 1:
            try SMCKit.shared.write(key.code, data[data.startIndex])
        case 4:
            try SMCKit.shared.write(key.code, data.littleEndianUInt32)
        default:
            throw SMCTransportError.unsupportedWriteSize(
                key: key.rawValue,
                size: data.count
            )
        }
    }
}

extension Data {
    init(littleEndian value: UInt32) {
        self.init([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    var littleEndianUInt32: UInt32 {
        precondition(count == MemoryLayout<UInt32>.size)
        return enumerated().reduce(into: UInt32(0)) { result, element in
            result |= UInt32(element.element) << UInt32(element.offset * 8)
        }
    }
}
