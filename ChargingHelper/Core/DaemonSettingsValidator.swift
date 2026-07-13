import Foundation
import smc_power

enum DaemonSettingsValidationError: Error, Equatable, Sendable {
    case incompatibleSchema(expected: Int, actual: Int)
    case chargeLimitOutOfRange(Int)
    case sailingDeltaOutOfRange(Int)
    case invalidSailingThreshold(chargeLimit: Int, sailingDelta: Int)
    case heatProtectionLimitOutOfRange(Int)
    case invalidMagSafeLEDState(UInt8)
}

struct DaemonSettingsValidator: Sendable {
    static let chargeLimitRange = 50...100
    static let sailingDeltaRange = 0...20
    static let heatProtectionLimitRange = 30...50

    let capabilities: DaemonCapabilities

    func validateAndNormalize(_ candidate: DaemonSettings) throws -> DaemonSettings {
        guard candidate.schemaVersion == DaemonSettings.currentSchemaVersion else {
            throw DaemonSettingsValidationError.incompatibleSchema(
                expected: DaemonSettings.currentSchemaVersion,
                actual: candidate.schemaVersion
            )
        }
        guard Self.chargeLimitRange.contains(candidate.chargeLimit) else {
            throw DaemonSettingsValidationError.chargeLimitOutOfRange(candidate.chargeLimit)
        }
        guard Self.sailingDeltaRange.contains(candidate.sailingDelta) else {
            throw DaemonSettingsValidationError.sailingDeltaOutOfRange(candidate.sailingDelta)
        }
        guard candidate.chargeLimit - candidate.sailingDelta >= 0 else {
            throw DaemonSettingsValidationError.invalidSailingThreshold(
                chargeLimit: candidate.chargeLimit,
                sailingDelta: candidate.sailingDelta
            )
        }
        guard Self.heatProtectionLimitRange.contains(candidate.heatProtectionLimit) else {
            throw DaemonSettingsValidationError.heatProtectionLimitOutOfRange(
                candidate.heatProtectionLimit
            )
        }
        guard MagSafeLEDState(rawValue: candidate.heatProtectionLEDStateRawValue) != nil else {
            throw DaemonSettingsValidationError.invalidMagSafeLEDState(
                candidate.heatProtectionLEDStateRawValue
            )
        }

        var normalized = candidate
        normalized.managementEnabled = candidate.managementEnabled && capabilities.chargingControl
        normalized.sailingModeEnabled = candidate.sailingModeEnabled && capabilities.chargingControl
        normalized.automaticDischarge =
            candidate.automaticDischarge && capabilities.automaticDischargeControl
        normalized.preventSleepUntilLimit = candidate.preventSleepUntilLimit && capabilities.sleepHooks
        normalized.heatProtectionEnabled =
            candidate.heatProtectionEnabled && capabilities.heatProtectionControl
        normalized.manageMagSafeLED = candidate.manageMagSafeLED && capabilities.magSafeLEDControl
        return normalized
    }
}
