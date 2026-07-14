import smc_power

/// Decides what charging/adapter/LED state the battery should be in, based
/// purely on where the battery percentage sits relative to the charge limit
/// (and, below the limit, whether sailing mode keeps it there).
///
/// This is the core of what used to be the ~90-line conditional chain in
/// `ChargingCoordinator.evaluate`. It's pulled out as its own type — a *policy*,
/// in the same sense as `HeatProtectionPolicy` and `ForceDischargePolicy` —
/// so each rule lives in one place, reads top-to-bottom as "which zone is
/// the battery in, and what does that zone mean", and can be reasoned about
/// (or tested) without needing a running `ChargingCoordinator`.
///
/// The only piece of mutable state involved is charge-limit hysteresis
/// (`hasReachedChargeLimit`), which is why it's threaded through explicitly
/// as `inout` rather than hidden as a stored property — the mutation is
/// visible at every call site instead of being an implicit side effect.
enum ChargeLimitPolicy {
    /// Where the battery percentage sits relative to the charge limit.
    private enum Zone {
        case aboveLimit
        case atLimit
        case belowLimit
    }

    static func evaluate(
        controlState: BatteryControlState,
        settings: ChargingSettingsSnapshot,
        stateWasCleared: Bool,
        hasReachedChargeLimit: inout Bool
    ) -> ChargingDecision {
        let batteryPercentage = settings.batteryPercentage(for: controlState)

        primeHysteresisIfNeeded(
            stateWasCleared: stateWasCleared,
            batteryPercentage: batteryPercentage,
            settings: settings,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        switch zone(batteryPercentage: batteryPercentage, chargeLimit: settings.chargeLimit) {
        case .aboveLimit:
            hasReachedChargeLimit = true
            return decisionAtOrAboveLimit(isAboveLimit: true, settings: settings)

        case .atLimit:
            hasReachedChargeLimit = true
            return decisionAtOrAboveLimit(isAboveLimit: false, settings: settings)

        case .belowLimit where settings.sailingModeEnabled:
            return sailingModeDecision(
                batteryPercentage: batteryPercentage,
                settings: settings,
                hasReachedChargeLimit: &hasReachedChargeLimit
            )

        case .belowLimit:
            return chargingTowardLimitDecision(
                settings: settings,
                reason: "Battery is below the charge limit of \(settings.chargeLimit)%"
            )
        }
    }

    private static func zone(batteryPercentage: Int, chargeLimit: Int) -> Zone {
        if batteryPercentage > chargeLimit { return .aboveLimit }
        if batteryPercentage == chargeLimit { return .atLimit }
        return .belowLimit
    }

    /// If state was just cleared (adapter reconnected, management just
    /// turned on) while already within the sailing range, treat the limit
    /// as already reached instead of charging straight to 100% first.
    private static func primeHysteresisIfNeeded(
        stateWasCleared: Bool,
        batteryPercentage: Int,
        settings: ChargingSettingsSnapshot,
        hasReachedChargeLimit: inout Bool
    ) {
        guard stateWasCleared, settings.sailingModeEnabled else { return }
        let sailingThreshold = settings.chargeLimit - settings.sailingModeLimit
        if batteryPercentage >= sailingThreshold {
            hasReachedChargeLimit = true
        }
    }

    /// Battery is at or above the limit: stop charging either way. Only the
    /// adapter behavior and the reported reason differ between the two.
    private static func decisionAtOrAboveLimit(
        isAboveLimit: Bool,
        settings: ChargingSettingsSnapshot
    ) -> ChargingDecision {
        ChargingDecision(
            desiredCharging: false,
            desiredAdapter: isAboveLimit ? !settings.automaticDischarge : true,
            desiredLED: settings.manageMagSafeLED ? .green : nil,
            reason: isAboveLimit
                ? "Battery is above the charge limit of \(settings.chargeLimit)%"
                : "Battery has reached the charge limit of \(settings.chargeLimit)%"
        )
    }

    /// Battery is below the limit with sailing mode on: hold below the
    /// limit once it's already been reached once, instead of immediately
    /// topping back up.
    private static func sailingModeDecision(
        batteryPercentage: Int,
        settings: ChargingSettingsSnapshot,
        hasReachedChargeLimit: inout Bool
    ) -> ChargingDecision {
        let sailingThreshold = settings.chargeLimit - settings.sailingModeLimit
        let inSailingRange = batteryPercentage >= sailingThreshold

        if inSailingRange && hasReachedChargeLimit {
            return ChargingDecision(
                desiredCharging: false,
                desiredAdapter: true,
                desiredLED: settings.manageMagSafeLED ? .green : nil,
                reason: "Sailing mode is maintaining charge below \(settings.chargeLimit)%"
            )
        }

        let droppedOutOfSailingRange = !inSailingRange && hasReachedChargeLimit
        hasReachedChargeLimit = false

        let reason: String =
            if inSailingRange {
                "Charging to reach charge limit of \(settings.chargeLimit)%"
            } else if droppedOutOfSailingRange {
                "Battery dropped below sailing threshold of \(sailingThreshold)%"
            } else {
                "Battery is below the charge limit of \(settings.chargeLimit)%"
            }

        return chargingTowardLimitDecision(settings: settings, reason: reason)
    }

    /// Shared "charge normally" outcome, used both outside sailing mode and
    /// when sailing mode decides it's time to top back up.
    private static func chargingTowardLimitDecision(
        settings: ChargingSettingsSnapshot,
        reason: String
    ) -> ChargingDecision {
        ChargingDecision(
            desiredCharging: true,
            desiredAdapter: true,
            desiredLED: settings.manageMagSafeLED ? .orange : nil,
            reason: reason
        )
    }
}
