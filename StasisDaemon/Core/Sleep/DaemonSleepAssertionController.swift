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
        // `kIOPMAssertionTypePreventSystemSleep` (not the idle-only
        // `kIOPMAssertPreventUserIdleSystemSleep`) so Sleep Prevention also
        // blocks Sleep chosen from the Apple menu, not just idle sleep.
        // Neither assertion type can block lid-close sleep — that's a macOS
        // thermal-safety rule no user-space assertion overrides, so the
        // pre-sleep charging cutoff (Gap A) must stay unconditional and not
        // assume this assertion prevents sleep.
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
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
