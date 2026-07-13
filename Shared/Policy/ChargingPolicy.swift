import Foundation
import smc_power

/// Plain policy input. It deliberately has no dependency on app defaults.
struct ChargingSettingsSnapshot: Equatable, Sendable {
    let chargeLimit: Int
    let useHardwarePercentage: Bool
    let sailingModeEnabled: Bool
    let sailingModeLimit: Int
    let automaticDischarge: Bool
    let manageMagSafeLED: Bool
    let heatProtectionEnabled: Bool
    let heatProtectionLimit: Int
    let heatProtectionMagSafeLEDState: MagSafeLEDState
    let disableSleepUntilChargeLimit: Bool

    init(settings: DaemonSettings, chargeLimitOverrideActive: Bool) {
        chargeLimit = chargeLimitOverrideActive ? 100 : settings.chargeLimit
        useHardwarePercentage = settings.useHardwarePercentage
        sailingModeEnabled = settings.sailingModeEnabled
        sailingModeLimit = settings.sailingDelta
        automaticDischarge = settings.automaticDischarge
        manageMagSafeLED = settings.manageMagSafeLED
        heatProtectionEnabled = settings.heatProtectionEnabled
        heatProtectionLimit = settings.heatProtectionLimit
        heatProtectionMagSafeLEDState =
            MagSafeLEDState(rawValue: settings.heatProtectionLEDStateRawValue)
            ?? .blinkOrangeSlow
        disableSleepUntilChargeLimit = settings.preventSleepUntilLimit
    }

    func batteryPercentage(for controlState: BatteryControlState) -> Int {
        useHardwarePercentage
            ? controlState.hardwareBatteryPercentage
            : controlState.batteryPercentage
    }
}

struct ChargingDecision: Equatable, Sendable {
    var desiredCharging: Bool?
    var desiredAdapter: Bool?
    var desiredLED: MagSafeLEDState?
    var reason: String?
}

enum ChargeLimitPolicy {
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
        let percentage = settings.batteryPercentage(for: controlState)
        primeHysteresisIfNeeded(
            stateWasCleared: stateWasCleared,
            batteryPercentage: percentage,
            settings: settings,
            hasReachedChargeLimit: &hasReachedChargeLimit
        )

        switch zone(batteryPercentage: percentage, chargeLimit: settings.chargeLimit) {
        case .aboveLimit:
            hasReachedChargeLimit = true
            return decisionAtOrAboveLimit(isAboveLimit: true, settings: settings)
        case .atLimit:
            hasReachedChargeLimit = true
            return decisionAtOrAboveLimit(isAboveLimit: false, settings: settings)
        case .belowLimit where settings.sailingModeEnabled:
            return sailingModeDecision(
                batteryPercentage: percentage,
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

    private static func primeHysteresisIfNeeded(
        stateWasCleared: Bool,
        batteryPercentage: Int,
        settings: ChargingSettingsSnapshot,
        hasReachedChargeLimit: inout Bool
    ) {
        guard stateWasCleared, settings.sailingModeEnabled else { return }
        if batteryPercentage >= settings.chargeLimit - settings.sailingModeLimit {
            hasReachedChargeLimit = true
        }
    }

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

    private static func sailingModeDecision(
        batteryPercentage: Int,
        settings: ChargingSettingsSnapshot,
        hasReachedChargeLimit: inout Bool
    ) -> ChargingDecision {
        let threshold = settings.chargeLimit - settings.sailingModeLimit
        let inSailingRange = batteryPercentage >= threshold
        if inSailingRange, hasReachedChargeLimit {
            return ChargingDecision(
                desiredCharging: false,
                desiredAdapter: true,
                desiredLED: settings.manageMagSafeLED ? .green : nil,
                reason: "Sailing mode is maintaining charge below \(settings.chargeLimit)%"
            )
        }

        let droppedOutOfRange = !inSailingRange && hasReachedChargeLimit
        hasReachedChargeLimit = false
        let reason =
            if inSailingRange {
                "Charging to reach charge limit of \(settings.chargeLimit)%"
            } else if droppedOutOfRange {
                "Battery dropped below sailing threshold of \(threshold)%"
            } else {
                "Battery is below the charge limit of \(settings.chargeLimit)%"
            }
        return chargingTowardLimitDecision(settings: settings, reason: reason)
    }

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

enum HeatProtectionPolicy {
    static func apply(
        to decision: inout ChargingDecision,
        controlState: BatteryControlState,
        settings: ChargingSettingsSnapshot
    ) {
        guard settings.heatProtectionEnabled,
              controlState.batteryTemperature > Double(settings.heatProtectionLimit)
        else { return }

        decision.desiredCharging = false
        decision.reason = "Battery temperature exceeds \(settings.heatProtectionLimit)°C"
        if settings.manageMagSafeLED {
            decision.desiredLED = settings.heatProtectionMagSafeLEDState
        }
    }
}

enum ForceDischargePolicy {
    static func apply(to decision: inout ChargingDecision, isActive: Bool) {
        guard isActive else { return }
        decision.desiredCharging = false
        decision.desiredAdapter = false
    }
}
