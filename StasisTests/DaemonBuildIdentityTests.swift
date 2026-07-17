import XCTest

@testable import Stasis

@MainActor
final class DaemonBuildIdentityTests: XCTestCase {
    func testExecutableHashMatchesKnownSHA256() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daemon-build-identity-\(UUID().uuidString)")
        try Data("stasis".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            DaemonBuildIdentity.executableHash(at: url),
            "e22a82b1d9c6cb74e4ea34318241be8ca37b13de359fe6c5cddb3903b61158bf"
        )
    }

    func testExecutableHashReturnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daemon-build-identity-missing-\(UUID().uuidString)")
        XCTAssertNil(DaemonBuildIdentity.executableHash(at: url))
    }

    func testCurrentExecutableHashIsStable() {
        let first = DaemonBuildIdentity.currentExecutableHash()
        XCTAssertNotNil(first)
        XCTAssertEqual(first, DaemonBuildIdentity.currentExecutableHash())
    }

    func testHealthPayloadWithoutExecutableHashStillDecodes() throws {
        let legacyPayload = Data(
            """
            {
              "schemaVersion": 1,
              "status": "ready",
              "daemonVersion": "1.0",
              "chargeControlMode": "firmware"
            }
            """.utf8
        )

        let health = try DaemonPayloadCodec.decode(DaemonHealth.self, from: legacyPayload)
        XCTAssertNil(health.executableHash)
        XCTAssertEqual(health.daemonVersion, "1.0")
    }
}
