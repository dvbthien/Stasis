import Foundation
import os.log
import smc_power

let logger = Logger(
    subsystem: "com.srimanachanta.stasis-daemon",
    category: "ServiceDelegate"
)

let battery: SMCBattery
let adapter: SMCAdapter
do {
    battery = try SMCBattery.probe()
    adapter = try SMCAdapter.probe()
} catch {
    logger.fault("Failed to probe SMC capabilities: \(error.localizedDescription)")
    exit(1)
}

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    let helper: ChargingHelper

    init(helper: ChargingHelper) {
        self.helper = helper
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: (any ChargingHelperProtocol).self
        )
        newConnection.exportedObject = helper

        logger.info("XPC connection accepted")

        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            logger.info("XPC connection invalidated, resetting SMC keys to defaults")
            self.helper.resetToDefaults()
            // Do NOT exit(0) here. This daemon is registered as a long-lived
            // SMAppService daemon via launchd, and a single client (the main
            // app) disconnecting — e.g. on app quit, or transiently across a
            // sleep/wake cycle — does not mean the daemon itself should die.
            // Exiting here would force launchd to relaunch the daemon (and
            // re-probe SMC) on every reconnect, which is both wasteful and,
            // if reconnects happen frequently, was the underlying driver of
            // the helper churn/memory growth this fix addresses. The daemon
            // is cheap to leave running and idle; SMC state is safely reset
            // above regardless of whether the process keeps living.
        }

        newConnection.resume()
        return true
    }
}

let helper = ChargingHelper(battery: battery, adapter: adapter)
let delegate = ServiceDelegate(helper: helper)
let listener = NSXPCListener(
    machServiceName: "com.srimanachanta.stasis-daemon"
)
listener.delegate = delegate
listener.resume()

dispatchMain()
