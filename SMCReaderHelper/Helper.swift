import Foundation
import os.log
import smc_power

final class Helper: NSObject, SMCReaderHelperProtocol {
    private let logger = Logger(
        subsystem: "com.srimanachanta.stasis.smc-reader-helper",
        category: "SMCReader"
    )

    func readAllMetrics(reply: @escaping @Sendable (Data?, String?) -> Void) {
        logger.debug("SMC telemetry request received")
        reply(encode(readAllMetrics()), nil)
    }

    private func readAllMetrics() -> SMCTelemetryMetrics {
        autoreleasepool {
            let battery = readBatteryMetricsSync()
            let adapter = readAdapterMetricsSync()
            return SMCTelemetryMetrics(
                batteryVoltage: battery.0,
                batteryCurrent: battery.1,
                batteryPower: battery.2,
                adapterVoltage: adapter.0,
                adapterCurrent: adapter.1,
                adapterPower: adapter.2
            )
        }
    }

    private func readBatteryMetricsSync() -> (Double, Double, Double) {
        do {
            let voltage = try SMCBattery.getVoltage()
            let current = try SMCBattery.getCurrent()
            return (voltage, current, voltage * current)
        } catch {
            logger.error("SMC battery metrics read failed: \(error.localizedDescription)")
            return (0, 0, 0)
        }
    }

    private func readAdapterMetricsSync() -> (Double, Double, Double) {
        do {
            var voltage = try SMCAdapter.getVoltage()
            var current = try SMCAdapter.getCurrent()
            if abs(voltage) < 0.1 { voltage = 0 }
            if abs(current) < 0.1 { current = 0 }
            return (voltage, current, voltage * current)
        } catch {
            logger.error("SMC adapter metrics read failed: \(error.localizedDescription)")
            return (0, 0, 0)
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        do {
            return try DaemonPayloadCodec.encode(value)
        } catch {
            logger.error("Could not encode SMC reader response: \(error.localizedDescription)")
            return nil
        }
    }
}
