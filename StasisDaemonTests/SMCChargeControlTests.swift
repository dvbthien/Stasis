import Foundation
import XCTest
@testable import smc_power

final class SMCChargeControlTests: XCTestCase {
    func testFirmwareKeysTakePrecedenceOverLegacyKeys() throws {
        let transport = MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
            .firmwareActivation: .init(size: 1, data: [0x00]),
            .firmwareUpperLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
            .firmwareLowerLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
        ])

        let battery = try SMCBattery.probe(using: transport)

        XCTAssertEqual(battery.capabilities.chargeControlMode, .firmware)
        XCTAssertTrue(battery.capabilities.firmwareChargeLimitControl)
        XCTAssertFalse(battery.capabilities.inhibitChargeControl)
    }

    func testInvalidFirmwarePlaceholderFallsBackToLegacy() throws {
        let transport = MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
            .firmwareActivation: .init(size: 0, data: []),
            .firmwareUpperLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
            .firmwareLowerLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
        ])

        let battery = try SMCBattery.probe(using: transport)

        XCTAssertEqual(battery.capabilities.chargeControlMode, .legacy)
    }

    func testEmptyFirmwarePayloadDoesNotSelectFirmwareMode() throws {
        let transport = MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
            .firmwareActivation: .init(size: 1, data: []),
            .firmwareUpperLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
            .firmwareLowerLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
        ])

        let battery = try SMCBattery.probe(using: transport)

        XCTAssertEqual(battery.capabilities.chargeControlMode, .legacy)
    }

    func testIncompleteFirmwareKeySetIsUnsupportedWithoutLegacyFallback() throws {
        let transport = MockSMCTransport([
            .firmwareActivation: .init(size: 1, data: [0x00]),
            .firmwareUpperLimit: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00]),
        ])

        let battery = try SMCBattery.probe(using: transport)

        XCTAssertEqual(battery.capabilities.chargeControlMode, .unsupported)
    }

    func testLegacyModeRequiresPairOrValidTahoeKey() throws {
        let paired = try SMCBattery.probe(using: MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
        ]))
        let incomplete = try SMCBattery.probe(using: MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00])
        ]))
        let tahoe = try SMCBattery.probe(using: MockSMCTransport([
            .tahoeCharging: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00])
        ]))
        let invalidTahoe = try SMCBattery.probe(using: MockSMCTransport([
            .tahoeCharging: .init(size: 1, data: [0x00])
        ]))

        XCTAssertEqual(paired.capabilities.chargeControlMode, .legacy)
        XCTAssertEqual(incomplete.capabilities.chargeControlMode, .unsupported)
        XCTAssertEqual(tahoe.capabilities.chargeControlMode, .legacy)
        XCTAssertEqual(invalidTahoe.capabilities.chargeControlMode, .unsupported)
    }

    func testPairedLegacyChargingWritesBothKeys() throws {
        let transport = MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
        ])
        let battery = try SMCBattery.probe(using: transport)

        try battery.setChargingEnabled(false)
        XCTAssertEqual(transport.writes, [
            .init(key: .legacyChargingPrimary, data: [0x02]),
            .init(key: .legacyChargingSecondary, data: [0x02]),
        ])
        XCTAssertFalse(try battery.getChargingEnabled())

        transport.removeAllWrites()
        try battery.setChargingEnabled(true)
        XCTAssertEqual(transport.writes, [
            .init(key: .legacyChargingPrimary, data: [0x00]),
            .init(key: .legacyChargingSecondary, data: [0x00]),
        ])
        XCTAssertTrue(try battery.getChargingEnabled())
    }

    func testTahoeLegacyChargingUsesFourByteValues() throws {
        let transport = MockSMCTransport([
            .tahoeCharging: .init(size: 4, data: [0x00, 0x00, 0x00, 0x00])
        ])
        let battery = try SMCBattery.probe(using: transport)

        try battery.setChargingEnabled(false)
        XCTAssertEqual(transport.writes, [
            .init(key: .tahoeCharging, data: [0x01, 0x00, 0x00, 0x00])
        ])

        transport.removeAllWrites()
        try battery.setChargingEnabled(true)
        XCTAssertEqual(transport.writes, [
            .init(key: .tahoeCharging, data: [0x00, 0x00, 0x00, 0x00])
        ])
    }

    func testAdapterKeyPriorityAndDisableValues() throws {
        let primaryTransport = MockSMCTransport([
            .adapterPrimary: .init(size: 1, data: [0x00]),
            .adapterSecondary: .init(size: 1, data: [0x00]),
            .tahoeAdapter: .init(size: 1, data: [0x00]),
        ])
        let primary = try SMCAdapter.probe(using: primaryTransport)
        try primary.setPowerEnabled(false)
        XCTAssertEqual(primaryTransport.writes, [
            .init(key: .adapterPrimary, data: [0x01])
        ])

        let secondaryTransport = MockSMCTransport([
            .adapterSecondary: .init(size: 1, data: [0x00]),
            .tahoeAdapter: .init(size: 1, data: [0x00]),
        ])
        let secondary = try SMCAdapter.probe(using: secondaryTransport)
        try secondary.setPowerEnabled(false)
        XCTAssertEqual(secondaryTransport.writes, [
            .init(key: .adapterSecondary, data: [0x01])
        ])

        let tahoeTransport = MockSMCTransport([
            .tahoeAdapter: .init(size: 1, data: [0x00])
        ])
        let tahoe = try SMCAdapter.probe(using: tahoeTransport)
        try tahoe.setPowerEnabled(false)
        XCTAssertEqual(tahoeTransport.writes, [
            .init(key: .tahoeAdapter, data: [0x08])
        ])
    }

    func testAdapterEnsureIsIdempotent() throws {
        let transport = MockSMCTransport([
            .adapterPrimary: .init(size: 1, data: [0x00])
        ])
        let adapter = try SMCAdapter.probe(using: transport)

        XCTAssertFalse(try adapter.ensurePowerEnabled(true))
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertTrue(try adapter.ensurePowerEnabled(false))
        XCTAssertFalse(try adapter.ensurePowerEnabled(false))
        XCTAssertEqual(transport.writes, [
            .init(key: .adapterPrimary, data: [0x01])
        ])
    }

    func testFirmwareReconcileUsesLittleEndianRequiredOrderAndThenNoOps() throws {
        let transport = firmwareTransport(active: 0, lower: 0, upper: 0)
        let battery = try SMCBattery.probe(using: transport)

        XCTAssertTrue(try battery.ensureFirmwareChargeLimit(lower: 48, upper: 50))
        XCTAssertEqual(transport.writes, [
            .init(key: .firmwareActivation, data: [0x00]),
            .init(key: .firmwareUpperLimit, data: [0x32, 0x00, 0x00, 0x00]),
            .init(key: .firmwareLowerLimit, data: [0x30, 0x00, 0x00, 0x00]),
            .init(key: .firmwareActivation, data: [0x02]),
        ])
        XCTAssertEqual(
            try battery.getFirmwareChargeLimit(),
            SMCFirmwareChargeLimitState(active: true, lower: 48, upper: 50)
        )

        transport.removeAllWrites()
        XCTAssertFalse(try battery.ensureFirmwareChargeLimit(lower: 48, upper: 50))
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testFirmwareLimitAtOneHundredDeactivatesInsteadOfRewritingBounds() throws {
        let transport = firmwareTransport(active: 2, lower: 75, upper: 80)
        let battery = try SMCBattery.probe(using: transport)

        XCTAssertTrue(try battery.ensureFirmwareChargeLimit(lower: 95, upper: 100))
        XCTAssertEqual(transport.writes, [
            .init(key: .firmwareActivation, data: [0x00])
        ])
    }

    func testFirmwareDisableIsIdempotent() throws {
        let transport = firmwareTransport(active: 2, lower: 75, upper: 80)
        let battery = try SMCBattery.probe(using: transport)

        XCTAssertTrue(try battery.ensureFirmwareChargeLimitDisabled())
        XCTAssertFalse(try battery.ensureFirmwareChargeLimitDisabled())
        XCTAssertEqual(transport.writes, [
            .init(key: .firmwareActivation, data: [0x00])
        ])
    }

    func testModeSpecificAPIsRejectWrongMode() throws {
        let legacy = try SMCBattery.probe(using: MockSMCTransport([
            .legacyChargingPrimary: .init(size: 1, data: [0x00]),
            .legacyChargingSecondary: .init(size: 1, data: [0x00]),
        ]))
        let firmware = try SMCBattery.probe(using: firmwareTransport(active: 0, lower: 0, upper: 0))

        XCTAssertThrowsError(try legacy.ensureFirmwareChargeLimit(lower: 70, upper: 80)) { error in
            XCTAssertEqual(
                error as? SMCBatteryError,
                .wrongChargeControlMode(required: .firmware, actual: .legacy)
            )
        }
        XCTAssertThrowsError(try firmware.setChargingEnabled(false)) { error in
            XCTAssertEqual(
                error as? SMCBatteryError,
                .wrongChargeControlMode(required: .legacy, actual: .firmware)
            )
        }
    }

    private func firmwareTransport(
        active: UInt8,
        lower: UInt32,
        upper: UInt32
    ) -> MockSMCTransport {
        MockSMCTransport([
            .firmwareActivation: .init(size: 1, data: [active]),
            .firmwareUpperLimit: .init(size: 4, data: Data(littleEndian: upper)),
            .firmwareLowerLimit: .init(size: 4, data: Data(littleEndian: lower)),
        ])
    }
}

private final class MockSMCTransport: SMCTransport, @unchecked Sendable {
    struct Entry: Sendable {
        let size: Int
        var data: Data

        init(size: Int, data: Data) {
            self.size = size
            self.data = data
        }

        init(size: Int, data: [UInt8]) {
            self.init(size: size, data: Data(data))
        }
    }

    struct Write: Equatable, Sendable {
        let key: SMCControlKey
        let data: Data

        init(key: SMCControlKey, data: Data) {
            self.key = key
            self.data = data
        }

        init(key: SMCControlKey, data: [UInt8]) {
            self.init(key: key, data: Data(data))
        }
    }

    private let lock = NSLock()
    private var entries: [SMCControlKey: Entry]
    private var recordedWrites: [Write] = []

    var writes: [Write] {
        lock.withLock { recordedWrites }
    }

    init(_ entries: [SMCControlKey: Entry]) {
        self.entries = entries
    }

    func dataSize(for key: SMCControlKey) throws -> Int? {
        lock.withLock { entries[key]?.size }
    }

    func read(_ key: SMCControlKey) throws -> Data {
        try lock.withLock {
            guard let entry = entries[key] else {
                throw SMCTransportError.keyNotFound(key.rawValue)
            }
            return entry.data
        }
    }

    func write(_ data: Data, to key: SMCControlKey) throws {
        try lock.withLock {
            guard var entry = entries[key] else {
                throw SMCTransportError.keyNotFound(key.rawValue)
            }
            guard entry.size == data.count else {
                throw SMCTransportError.invalidDataSize(
                    key: key.rawValue,
                    expected: entry.size,
                    actual: data.count
                )
            }
            entry.data = data
            entries[key] = entry
            recordedWrites.append(Write(key: key, data: data))
        }
    }

    func removeAllWrites() {
        lock.withLock {
            recordedWrites.removeAll()
        }
    }
}
