import Foundation
import os.log
import smc_power

/// Owns fast SMC polling (voltage/current/power for battery and adapter) and
/// the XPC connection it requires — together, as a single unit.
///
/// This used to be split across `BatteryService` and `SMCReaderConnection`,
/// with `BatteryService` responsible for remembering to call
/// `xpcManager.disconnect()` at every place polling could stop (capability
/// probe finishing, fast polling being disabled, a one-off scheduled poll
/// completing). That repetition was exactly how the connection got left open
/// for hours in the first place — it only takes one missed call site for the
/// XPC Service to be kept alive indefinitely. Folding both concerns into one
/// class means there is now exactly one place that decides "is anything still
/// using this connection?", so it can't drift out of sync.
///
/// `BatteryService` only ever calls `start()`, `stop()`, `scheduleSinglePoll()`,
/// `loadCapabilities()`, and `shutdown()` — it has no direct access to the underlying
/// `SMCReaderConnection` at all.
@MainActor
final class SMCMetricsPoller {
    /// How often to re-read SMC while polling is continuously active.
    /// Kept as a var (not `static let`) so a future adaptive-interval change
    /// (e.g. slow down when readings are stable) only has to touch this one
    /// property instead of a hardcoded `.seconds(1)` buried in a loop.
    var pollInterval: Duration = .seconds(1)

    private let xpcManager: SMCReaderConnection
    private let onReading: (SMCBatteryReading, SMCAdapterReading) -> Void
    private let logger = Logger.stasis("SMCMetricsPoller")

    private var continuousPollTask: Task<Void, Never>?
    private var oneShotPollTask: Task<Void, Never>?

    private var isPolling: Bool { continuousPollTask != nil }

    /// - Parameters:
    ///   - serviceName: mach service name of the read-only SMC helper.
    ///   - onReading: called on the main actor with every successful poll.
    init(
        serviceName: String,
        onReading: @escaping (SMCBatteryReading, SMCAdapterReading) -> Void
    ) {
        self.xpcManager = SMCReaderConnection(serviceName: serviceName)
        self.onReading = onReading
    }

    /// Starts continuous polling at `pollInterval`. No-op if already running.
    func start() {
        guard continuousPollTask == nil else {
            logger.warning("Fast polling already enabled")
            return
        }

        logger.info("Enabling fast SMC polling")
        continuousPollTask = Task {
            await self.pollOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { break }
                await self.pollOnce()
            }
        }
    }

    /// Stops continuous polling and closes the XPC connection.
    func stop() {
        guard continuousPollTask != nil else {
            logger.warning("Fast polling not enabled")
            return
        }

        logger.info("Disabling fast SMC polling")
        continuousPollTask?.cancel()
        continuousPollTask = nil
        xpcManager.disconnect()
    }

    /// Schedules one delayed refresh after a charging command so UI state can
    /// catch the resulting power-flow change without keeping fast polling on.
    func scheduleSinglePoll(delay: Duration = .seconds(3)) {
        oneShotPollTask?.cancel()
        oneShotPollTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.pollOnce()
        }
    }

    /// Probes device capabilities once. Closes the connection afterwards
    /// since this is a one-shot call with nothing else waiting on it.
    func loadCapabilities() async -> DeviceCapabilities? {
        guard let helper = getHelper(context: "loading capabilities") else { return nil }

        let capabilities = await withCheckedContinuation { continuation in
            helper.getCapabilities { chargingControl, adapterControl, hasMagSafe, magsafeLEDControl in
                continuation.resume(
                    returning: DeviceCapabilities(
                        chargingControl: chargingControl,
                        adapterControl: adapterControl,
                        hasMagSafe: hasMagSafe,
                        magsafeLEDControl: magsafeLEDControl
                    )
                )
            }
        }

        xpcManager.disconnect()
        return capabilities
    }

    /// Tears down everything: cancels any pending poll and closes the
    /// connection. Call when the owning service is shutting down.
    func shutdown() {
        continuousPollTask?.cancel()
        continuousPollTask = nil
        oneShotPollTask?.cancel()
        oneShotPollTask = nil
        xpcManager.disconnect()
    }

    private func pollOnce() async {
        guard let helper = getHelper(context: "polling") else { return }

        let reading = await withCheckedContinuation { continuation in
            helper.readAllMetrics { batteryVoltage, batteryCurrent, batteryPower, adapterVoltage, adapterCurrent, adapterPower in
                continuation.resume(
                    returning: (
                        SMCBatteryReading(
                            batteryVoltage: batteryVoltage,
                            batteryCurrent: batteryCurrent,
                            batteryPower: batteryPower
                        ),
                        SMCAdapterReading(
                            adapterVoltage: adapterVoltage,
                            adapterCurrent: adapterCurrent,
                            adapterPower: adapterPower
                        )
                    )
                )
            }
        }

        onReading(reading.0, reading.1)

        if !isPolling {
            xpcManager.disconnect()
        }
    }

    private func getHelper(context: String) -> HelperProtocol? {
        let logger = self.logger
        guard
            let helper = xpcManager.getHelper(errorHandler: { error in
                logger.error("XPC error while \(context): \(error.localizedDescription)")
            })
        else {
            logger.warning("Helper unavailable while \(context)")
            return nil
        }
        return helper
    }
}
