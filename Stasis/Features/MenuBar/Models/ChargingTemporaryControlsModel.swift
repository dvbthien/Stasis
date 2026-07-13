import Foundation
import Observation
import os.log

@MainActor
@Observable
final class ChargingTemporaryControlsModel {
    private let daemonManager = ChargingDaemonManager.shared
    private let logger = Logger.stasis("ChargingTemporaryControls")

    var chargeLimitOverrideActive: Bool {
        daemonManager.daemonSnapshot?.policy.chargeLimitOverrideActive ?? false
    }

    var forceDischargeActive: Bool {
        daemonManager.daemonSnapshot?.policy.forceDischargeActive ?? false
    }

    func setChargeLimitOverride(_ enabled: Bool) {
        Task { [daemonManager, logger] in
            do {
                try await daemonManager.setChargeLimitOverride(enabled)
            } catch {
                logger.error("Charge-limit override failed: \(error.localizedDescription)")
            }
        }
    }

    func setForceDischarge(_ enabled: Bool) {
        Task { [daemonManager, logger] in
            do {
                try await daemonManager.setForceDischarge(enabled)
            } catch {
                logger.error("Force discharge failed: \(error.localizedDescription)")
            }
        }
    }
}
