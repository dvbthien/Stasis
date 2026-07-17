import IOKit.pwr_mgt
import os.log

protocol DaemonSleepAssertionControlling: Sendable {
    func update(shouldPreventSleep: Bool) async
}

actor DaemonSleepAssertionController: DaemonSleepAssertionControlling {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private let logger = Logger(
        subsystem: Constants.Identity.daemon,
        category: "SleepAssertion"
    )

    func update(shouldPreventSleep: Bool) {
        if shouldPreventSleep, assertionID == IOPMAssertionID(kIOPMNullAssertionID) {
            acquire()
        } else if !shouldPreventSleep,
                  assertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            release()
        }
    }

    private func acquire() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Stasis daemon: Charging towards charge limit" as CFString,
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
