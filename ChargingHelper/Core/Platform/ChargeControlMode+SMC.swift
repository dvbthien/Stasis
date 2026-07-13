import smc_power

extension ChargeControlMode {
    init(smcMode: SMCChargeControlMode) {
        switch smcMode {
        case .unsupported: self = .unsupported
        case .legacy: self = .legacy
        case .firmware: self = .firmware
        }
    }
}
