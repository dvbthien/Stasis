import smc_power

/// The outcome of evaluating charging policy for one tick: what the
/// hardware should be told to do, and why. Kept as a plain value type so
/// policy logic (`ChargeLimitPolicy`, `HeatProtectionPolicy`,
/// `ForceDischargePolicy`) can stay pure and testable — it computes a
/// `ChargingDecision`, and `ChargingCoordinator` is the only place that turns it
/// into side effects.
///
/// `nil` for any field means "don't touch this" rather than "turn it off" —
/// each field is applied independently by `ChargingCoordinator`, only when the
/// device actually supports controlling it.
struct ChargingDecision: Equatable, Sendable {
    var desiredCharging: Bool?
    var desiredAdapter: Bool?
    var desiredLED: MagSafeLEDState?
    var reason: String?
}
