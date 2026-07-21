import Defaults
import Foundation

enum PercentageDisplayLocation: String, Defaults.Serializable, CaseIterable, Identifiable {
    case hidden
    case nextToIcon
    case insideIcon

    var id: String { rawValue }
}

extension Defaults.Keys {
    // General
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)

    // Status Icon
    static let batteryPercentageDisplayLocation = Key<PercentageDisplayLocation>(
        "batteryPercentageDisplayLocation", default: .nextToIcon)
    static let showBatteryStateInStatusIcon = Key<Bool>(
        "showBatteryStateInStatusIcon", default: true)

    // Notifications
    static let disableNotifications = Key<Bool>("disableNotifications", default: false)
    static let showChargingStatusChangedNotification = Key<Bool>(
        "showChargingStatusChangedNotification", default: true)

    // Menu Dashboard
    static let showTimeTillDischarge = Key<Bool>("showTimeTillDischarge", default: true)
    static let showBatteryCycleCount = Key<Bool>("showBatteryCycleCount", default: true)
    static let showBatteryHealth = Key<Bool>("showBatteryHealth", default: true)
    static let showBatteryTemperature = Key<Bool>("showBatteryTemperature", default: false)
    static let showPowerSource = Key<Bool>("showPowerSource", default: false)
    static let showUptime = Key<Bool>("showUptime", default: true)
    static let showBatteryMode = Key<Bool>("showBatteryMode", default: true)
    static let showInternalPower = Key<Bool>("showInternalPower", default: true)
    static let showExternalPower = Key<Bool>("showExternalPower", default: true)
    static let showPowerDistribution = Key<Bool>("showPowerDistribution", default: false)

    // Advanced
    static let restartOnClose = Key<Bool>("restartOnClose", default: false)

    // Onboarding
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)
}
