import Foundation
import os.log
import smc_power

let logger = Logger(
    subsystem: "com.srimanachanta.stasis-daemon",
    category: "DaemonStartup"
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

let capabilities = DaemonCapabilities(
    chargeControlMode: ChargeControlMode(smcMode: battery.capabilities.chargeControlMode),
    adapterControl: adapter.capabilities.powerControl,
    magSafeLEDKeyAvailable: adapter.capabilities.magSafeControl
)
let daemonVersion = Bundle.main.object(
    forInfoDictionaryKey: "CFBundleShortVersionString"
) as? String ?? "1.0"
let hardware = ChargingHelper(battery: battery, adapter: adapter)
let clients = DaemonClientRegistry()

let settingsStore: DaemonSettingsStore
do {
    settingsStore = try DaemonSettingsStore(
        persistence: UserDefaultsDaemonSettingsPersistence(),
        capabilities: capabilities
    )
} catch {
    logger.fault("Failed to load daemon settings: \(error.localizedDescription)")
    exit(1)
}

let stateStore = DaemonStateStore(
    capabilities: capabilities,
    hardware: hardware,
    daemonVersion: daemonVersion
)
let commandHandler = ChargingDaemonCommandHandler(
    settingsStore: settingsStore,
    stateStore: stateStore,
    hardware: hardware,
    capabilities: capabilities,
    daemonVersion: daemonVersion,
    clients: clients
)

let clientValidator = DaemonClientValidator.forCurrentBuild()
if clientValidator.isUsingAdHocRequirement {
    logger.warning(
        "Daemon has no Team ID; restricting XPC clients by app identifier for this local build"
    )
}

let server = StasisDaemonXPCServer(
    commandHandler: commandHandler,
    clientValidator: clientValidator,
    clients: clients
)
server.start()
logger.info("Stasis daemon XPC server started")

dispatchMain()
