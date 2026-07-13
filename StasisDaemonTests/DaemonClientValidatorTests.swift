import Foundation
import Security
import XCTest

final class DaemonClientValidatorTests: XCTestCase {
    func testReleaseRequirementPinsIdentifierTeamAndSafeEntitlements() {
        let requirement = StasisCodeSigningRequirement.make(
            teamIdentifier: "TEAM123",
            debugBuild: false
        )

        XCTAssertTrue(requirement.contains("identifier \"com.srimanachanta.stasis\""))
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"TEAM123\""))
        XCTAssertTrue(requirement.contains("com.apple.security.get-task-allow"))
        XCTAssertTrue(requirement.contains("com.apple.security.cs.allow-jit"))
    }

    func testAdHocRequirementPinsAppIdentifierInDebugAndRelease() {
        let debugRequirement = StasisCodeSigningRequirement.make(
            teamIdentifier: nil,
            debugBuild: true
        )
        let releaseRequirement = StasisCodeSigningRequirement.make(
            teamIdentifier: nil,
            debugBuild: false
        )

        XCTAssertEqual(debugRequirement, "identifier \"com.srimanachanta.stasis\"")
        XCTAssertEqual(releaseRequirement, debugRequirement)
    }

    func testReleaseRequirementParsesWithSecurityFramework() {
        let source = StasisCodeSigningRequirement.make(
            teamIdentifier: "TEAM123",
            debugBuild: false
        )
        var requirement: SecRequirement?

        let status = SecRequirementCreateWithString(
            source as CFString,
            [],
            &requirement
        )

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }
}
