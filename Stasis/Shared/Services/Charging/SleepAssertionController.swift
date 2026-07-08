import IOKit.pwr_mgt
import os.log

/// Owns the single IOPM "prevent idle sleep" assertion used while the Mac is
/// actively charging toward the charge limit, so it isn't put to sleep
/// before reaching it.
///
/// Pulled out of `ChargingCoordinator` because the assertion's create/release
/// dance — checking the sentinel ID, calling the right `IOPMAssertion*`
/// function, logging the result — is a self-contained concern that has
/// nothing to do with charging policy. `ChargingCoordinator` just calls
/// `update(shouldPreventSleep:)` once per evaluation.
@MainActor
final class SleepAssertionController {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private let logger = Logger.stasis("SleepAssertionController")

    private var isActive: Bool {
        assertionID != IOPMAssertionID(kIOPMNullAssertionID)
    }

    /// Creates or releases the assertion to match the desired state.
    /// No-op if already in the desired state.
    func update(shouldPreventSleep: Bool) {
        if shouldPreventSleep && !isActive {
            acquire()
        } else if !shouldPreventSleep && isActive {
            release()
        }
    }

    private func acquire() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Stasis: Charging towards charge limit" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            logger.info("Sleep assertion created")
        } else {
            logger.error("Failed to create sleep assertion: \(result)")
        }
    }

    private func release() {
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        logger.info("Sleep assertion released")
    }
}
