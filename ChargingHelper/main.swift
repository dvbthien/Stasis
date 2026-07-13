import Foundation
import Darwin
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
    daemonVersion: daemonVersion
)
let runtime = DaemonRuntimeCoordinator(
    settingsStore: settingsStore,
    stateStore: stateStore,
    hardware: hardware,
    clients: clients
)
let managementEngine = BatteryManagementEngine(
    capabilities: capabilities,
    settingsStore: settingsStore,
    stateStore: stateStore,
    hardware: hardware
)
let commandHandler = ChargingDaemonCommandHandler(
    settingsStore: settingsStore,
    stateStore: stateStore,
    runtime: runtime,
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
let ioKitMonitor = DaemonIOKitMonitor()
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler {
    logger.info("Stasis daemon received SIGTERM; stopping process-owned resources")
    Task { @MainActor in
        server.stop()
        ioKitMonitor.stop()
        await runtime.shutdown()
        CFRunLoopStop(CFRunLoopGetMain())
    }
}
terminationSource.resume()

Task { @MainActor in
    await runtime.installIOKitRefreshHandler { reason in
        await ioKitMonitor.refresh(reason: reason)
    }
    await runtime.installManagementEngine(managementEngine)
    let initialUpdate = ioKitMonitor.start { update in
        Task {
            await runtime.handlePowerSourceUpdate(update)
        }
    }
    if let initialUpdate {
        await runtime.handlePowerSourceUpdate(initialUpdate)
    }
    server.start()
    logger.info("Stasis daemon XPC server started with initial IOKit snapshot")
}

RunLoop.main.run()
