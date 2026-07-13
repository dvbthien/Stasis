import Foundation
import Security

protocol DaemonClientValidating: Sendable {
    var codeSigningRequirement: String { get }
    func isValid(processIdentifier: pid_t) -> Bool
}

struct DaemonClientValidator: DaemonClientValidating {
    let codeSigningRequirement: String
    let isUsingAdHocRequirement: Bool

    static func forCurrentBuild() -> DaemonClientValidator {
        let teamIdentifier = currentProcessTeamIdentifier()

        #if DEBUG
            let debugBuild = true
        #else
            let debugBuild = false
        #endif

        return DaemonClientValidator(
            codeSigningRequirement: StasisCodeSigningRequirement.make(
                teamIdentifier: teamIdentifier,
                debugBuild: debugBuild
            ),
            isUsingAdHocRequirement: teamIdentifier == nil
        )
    }

    func isValid(processIdentifier: pid_t) -> Bool {
        let attributes = [kSecGuestAttributePid: processIdentifier] as CFDictionary
        var code: SecCode?
        guard
            SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
            let code
        else {
            return false
        }

        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(
                codeSigningRequirement as CFString,
                [],
                &requirement
            ) == errSecSuccess,
            let requirement
        else {
            return false
        }

        return SecCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement
        ) == errSecSuccess
    }

    private static func currentProcessTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            return nil
        }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
            let dictionary = information as? [String: Any]
        else {
            return nil
        }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

enum StasisCodeSigningRequirement {
    static let appIdentifier = "com.srimanachanta.stasis"

    static func make(teamIdentifier: String?, debugBuild: Bool) -> String {
        var clauses = ["identifier \"\(appIdentifier)\""]

        if let teamIdentifier {
            clauses.append("anchor apple generic")
            clauses.append("certificate leaf[subject.OU] = \"\(teamIdentifier)\"")
            clauses.append(
                "!(entitlement[\"com.apple.security.cs.disable-library-validation\"] /* exists */)"
            )
            clauses.append(
                "!(entitlement[\"com.apple.security.cs.allow-unsigned-executable-memory\"] /* exists */)"
            )
            clauses.append(
                "!(entitlement[\"com.apple.security.cs.allow-jit\"] /* exists */)"
            )
            if !debugBuild {
                clauses.append(
                    "!(entitlement[\"com.apple.security.get-task-allow\"] /* exists */)"
                )
            }
        }

        return clauses.joined(separator: " and ")
    }
}
