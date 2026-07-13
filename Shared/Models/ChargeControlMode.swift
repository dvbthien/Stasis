import Foundation
import smc_power

/// Describes which SMC mechanism owns charge-limit enforcement.
///
/// The daemon will detect this from usable SMC keys rather than the reported
/// macOS version. Phase 1 only defines the wire contract; probing is added in
/// the SMC migration phase.
enum ChargeControlMode: String, Codable, CaseIterable, Sendable {
    case unsupported
    case legacy
    case firmware
}

extension ChargeControlMode {
    init(smcMode: SMCChargeControlMode) {
        switch smcMode {
        case .unsupported: self = .unsupported
        case .legacy: self = .legacy
        case .firmware: self = .firmware
        }
    }
}
