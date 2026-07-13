import Foundation

enum DaemonPowerSourceUpdateReason: Equatable, Sendable {
    case initial
    case interestNotification
    case wake
    case settingsRefresh
    case hardwareRefresh
}

struct DaemonPowerSourceUpdate: Equatable, Sendable {
    var battery: DaemonBatterySnapshot
    var adapter: DaemonAdapterSnapshot
    var reason: DaemonPowerSourceUpdateReason
}
