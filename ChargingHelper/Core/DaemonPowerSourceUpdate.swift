import Foundation

enum DaemonPowerSourceUpdateReason: Sendable {
    case initial
    case interestNotification
    case wake
}

struct DaemonPowerSourceUpdate: Equatable, Sendable {
    var battery: DaemonBatterySnapshot
    var adapter: DaemonAdapterSnapshot
    var reason: DaemonPowerSourceUpdateReason
}
