import Foundation

/// Describes which SMC mechanism owns charge-limit enforcement.
///
/// The daemon detects this from usable SMC keys rather than the reported
/// macOS version.
enum ChargeControlMode: String, Codable, CaseIterable, Sendable {
    case unsupported
    case legacy
    case firmware
}
