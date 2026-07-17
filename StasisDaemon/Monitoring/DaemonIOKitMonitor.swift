import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import os.log

private enum IOPowerMessage {
    // IOMessage.h defines these through iokit_common_msg(...), a C macro that
    // Swift cannot import. sys_iokit is 0xE0000000 and sub_iokit_common is 0.
    static let canSystemSleep: UInt32 = 0xE0000270
    static let systemWillSleep: UInt32 = 0xE0000280
    static let systemHasPoweredOn: UInt32 = 0xE0000300
}

@MainActor
final class DaemonIOKitMonitor {
    private var batteryNotificationPort: IONotificationPortRef?
    private var batteryInterestNotification: io_object_t = 0
    private var batteryService: io_service_t = 0

    private var powerNotificationPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var rootPowerPort: io_connect_t = 0

    private var onUpdate: (@Sendable (DaemonPowerSourceUpdate) -> Void)?
    private let logger = Logger(
        subsystem: Constants.Identity.daemon,
        category: "IOKitMonitor"
    )

    nonisolated init() {}

    func start(
        onUpdate: @escaping @Sendable (DaemonPowerSourceUpdate) -> Void
    ) -> DaemonPowerSourceUpdate? {
        guard self.onUpdate == nil else { return readUpdate(reason: .initial) }
        self.onUpdate = onUpdate
        registerBatteryNotifications()
        registerPowerNotifications()
        return readUpdate(reason: .initial)
    }

    func refresh(reason: DaemonPowerSourceUpdateReason) -> DaemonPowerSourceUpdate? {
        readUpdate(reason: reason)
    }

    func stop() {
        if batteryInterestNotification != 0 {
            IOObjectRelease(batteryInterestNotification)
            batteryInterestNotification = 0
        }
        destroyNotificationPort(&batteryNotificationPort)

        if powerNotifier != 0 {
            IODeregisterForSystemPower(&powerNotifier)
            powerNotifier = 0
        }
        if rootPowerPort != 0 {
            IOServiceClose(rootPowerPort)
            rootPowerPort = 0
        }
        destroyNotificationPort(&powerNotificationPort)

        if batteryService != 0 {
            IOObjectRelease(batteryService)
            batteryService = 0
        }
        onUpdate = nil
    }

    private func registerBatteryNotifications() {
        batteryService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard batteryService != 0 else {
            logger.error("AppleSmartBattery service is unavailable")
            return
        }

        batteryNotificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let batteryNotificationPort else {
            logger.error("Could not create battery notification port")
            return
        }
        addToMainRunLoop(batteryNotificationPort)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceInterestCallback = { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<DaemonIOKitMonitor>.fromOpaque(context)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.emitUpdate(reason: .interestNotification)
            }
        }

        let result = IOServiceAddInterestNotification(
            batteryNotificationPort,
            batteryService,
            kIOGeneralInterest,
            callback,
            context,
            &batteryInterestNotification
        )
        guard result == KERN_SUCCESS else {
            logger.error("Could not register battery interest notification: \(result)")
            return
        }
        logger.info("Registered AppleSmartBattery interest notifications")
    }

    private func registerPowerNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceInterestCallback = { context, _, messageType, messageArgument in
            guard let context else { return }
            let monitor = Unmanaged<DaemonIOKitMonitor>.fromOpaque(context)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                switch messageType {
                case IOPowerMessage.canSystemSleep, IOPowerMessage.systemWillSleep:
                    IOAllowPowerChange(
                        monitor.rootPowerPort,
                        Int(bitPattern: messageArgument)
                    )
                case IOPowerMessage.systemHasPoweredOn:
                    monitor.emitUpdate(reason: .wake)
                default:
                    break
                }
            }
        }

        rootPowerPort = IORegisterForSystemPower(
            context,
            &powerNotificationPort,
            callback,
            &powerNotifier
        )
        guard rootPowerPort != 0, let powerNotificationPort else {
            logger.error("Could not register system power notifications")
            return
        }
        addToMainRunLoop(powerNotificationPort)
        logger.info("Registered system wake notifications")
    }

    private func emitUpdate(reason: DaemonPowerSourceUpdateReason) {
        guard let update = readUpdate(reason: reason) else { return }
        onUpdate?(update)
    }

    private func readUpdate(
        reason: DaemonPowerSourceUpdateReason
    ) -> DaemonPowerSourceUpdate? {
        guard batteryService != 0 else { return nil }

        let powerInfo = powerSourceInfo() as? [String: Any]
        let percentages = batteryPercentages(powerInfo: powerInfo)
        let capacities = batteryCapacities()
        let isCharging = powerInfo?[kIOPSIsChargingKey] as? Bool ?? false
        let externalConnected: Bool = propertyValue(
            batteryService,
            key: "ExternalConnected"
        ) ?? false
        let physicallyConnected = externalConnected || adapterIsPhysicallyConnected()

        let battery = DaemonBatterySnapshot(
            displayedPercentage: percentages.displayed,
            hardwarePercentage: percentages.hardware,
            isCharging: isCharging,
            timeRemaining: timeRemaining(powerInfo: powerInfo, isCharging: isCharging),
            temperature: batteryTemperature(powerInfo: powerInfo) ?? 0,
            health: capacities.design > 0 ? (capacities.max * 100) / capacities.design : 100,
            cycleCount: propertyValue(batteryService, key: "CycleCount") ?? 0
        )
        let adapter = DaemonAdapterSnapshot(physicallyConnected: physicallyConnected)

        logger.debug(
            "IOKit update reason=\(String(describing: reason), privacy: .public) battery=\(battery.displayedPercentage)% charging=\(battery.isCharging) adapter=\(adapter.physicallyConnected)"
        )
        return DaemonPowerSourceUpdate(
            battery: battery,
            adapter: adapter,
            reason: reason
        )
    }

    private func powerSourceInfo() -> CFDictionary? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        guard let source = sources.first else { return nil }
        return IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue()
    }

    private func propertyValue<T>(_ service: io_service_t, key: String) -> T? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        return property.takeRetainedValue() as? T
    }

    private func batteryPercentages(powerInfo: [String: Any]?) -> (
        displayed: Int,
        hardware: Int
    ) {
        let displayed = powerInfo?[kIOPSCurrentCapacityKey] as? Int ?? 0
        let rawCurrent: Int = propertyValue(
            batteryService,
            key: "AppleRawCurrentCapacity"
        ) ?? 0
        let rawMax: Int = propertyValue(
            batteryService,
            key: "AppleRawMaxCapacity"
        ) ?? 0

        if rawMax > 0 {
            return (displayed, (rawCurrent * 100) / rawMax)
        }
        let hardware: Int = propertyValue(
            batteryService,
            key: "CurrentCapacity"
        ) ?? displayed
        return (displayed, hardware)
    }

    private func timeRemaining(powerInfo: [String: Any]?, isCharging: Bool) -> Int {
        let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        guard
            let value = powerInfo?[key] as? Int,
            value > 0,
            value != Int(kIOPSTimeRemainingUnknown)
        else {
            return -1
        }
        return value
    }

    private func batteryTemperature(powerInfo: [String: Any]?) -> Double? {
        if let temperature = powerInfo?[kIOPSTemperatureKey] as? Int, temperature > 0 {
            return celsius(fromDecikelvin: temperature)
        }
        guard
            let temperature: Int = propertyValue(batteryService, key: "Temperature"),
            temperature > 0,
            temperature <= 5_000
        else {
            return nil
        }
        return celsius(fromDecikelvin: temperature)
    }

    private func celsius(fromDecikelvin value: Int) -> Double? {
        let temperature = (Double(value) / 10) - 273.15
        return (0...80).contains(temperature) ? temperature : nil
    }

    private func batteryCapacities() -> (max: Int, design: Int) {
        let maximum: Int = propertyValue(
            batteryService,
            key: "AppleRawMaxCapacity"
        ) ?? 0
        let design: Int = propertyValue(
            batteryService,
            key: "DesignCapacity"
        ) ?? 0
        return (maximum, design)
    }

    private func adapterIsPhysicallyConnected() -> Bool {
        guard
            let details: [String: Any] = propertyValue(
                batteryService,
                key: "AdapterDetails"
            ),
            let watts = details["Watts"] as? Int
        else {
            return false
        }
        return watts > 0
    }

    private func addToMainRunLoop(_ port: IONotificationPortRef) {
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func destroyNotificationPort(_ port: inout IONotificationPortRef?) {
        guard let currentPort = port else { return }
        let source = IONotificationPortGetRunLoopSource(currentPort).takeUnretainedValue()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        IONotificationPortDestroy(currentPort)
        port = nil
    }
}
