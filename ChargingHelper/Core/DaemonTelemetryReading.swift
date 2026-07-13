struct DaemonTelemetryReading: Equatable, Sendable {
    var batteryAvailable = false
    var adapterAvailable = false

    var batteryVoltage: Double = 0
    var batteryCurrent: Double = 0
    var batteryPower: Double = 0

    var adapterVoltage: Double = 0
    var adapterCurrent: Double = 0
    var adapterPower: Double = 0
}
