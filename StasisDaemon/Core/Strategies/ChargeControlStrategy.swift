import Foundation

/// Mode-specific charge-control logic. The charge-control mode is fixed when
/// the SMC is probed, so exactly one strategy exists per daemon lifetime and
/// each strategy owns the hardware bookkeeping for its own mode.
protocol ChargeControlStrategizing: Actor {
    /// Reconciles hardware while management is enabled and the adapter is
    /// connected. Returns whether the power path changed.
    func reconcileManagement(
        context: DaemonManagementContext,
        stateWasCleared: Bool
    ) async throws -> Bool

    /// Applies defaults when management is disabled or the adapter is
    /// disconnected. Returns whether the power path changed.
    func applySystemDefaults(reason: String) async throws -> Bool

    /// Restores stock hardware behavior before shutdown or uninstall.
    func restoreHardwareDefaults(reason: String) async throws -> Bool
}
