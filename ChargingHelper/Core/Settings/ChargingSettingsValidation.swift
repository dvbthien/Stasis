import Foundation

enum ChargingSettingsValidationError: Error, Equatable, Sendable {
    case chargeLimitOutOfRange(Int)
    case sailingDeltaOutOfRange(Int)
    case invalidSailingThreshold(chargeLimit: Int, sailingDelta: Int)
    case heatProtectionLimitOutOfRange(Int)
}

enum ChargingSettingsValidation {
    static let chargeLimitRange = 50...100
    static let sailingDeltaRange = 0...20
    static let heatProtectionLimitRange = 30...50

    static func validate(_ settings: ChargingThresholdSettings) throws {
        guard chargeLimitRange.contains(settings.chargeLimit) else {
            throw ChargingSettingsValidationError.chargeLimitOutOfRange(settings.chargeLimit)
        }
        guard sailingDeltaRange.contains(settings.sailingDelta) else {
            throw ChargingSettingsValidationError.sailingDeltaOutOfRange(settings.sailingDelta)
        }
        guard settings.chargeLimit - settings.sailingDelta >= chargeLimitRange.lowerBound else {
            throw ChargingSettingsValidationError.invalidSailingThreshold(
                chargeLimit: settings.chargeLimit,
                sailingDelta: settings.sailingDelta
            )
        }
        if settings.sailingModeEnabled, settings.sailingDelta == 0 {
            throw ChargingSettingsValidationError.invalidSailingThreshold(
                chargeLimit: settings.chargeLimit,
                sailingDelta: settings.sailingDelta
            )
        }
    }

    static func validate(_ settings: HeatProtectionSettings) throws {
        guard heatProtectionLimitRange.contains(settings.temperatureLimit) else {
            throw ChargingSettingsValidationError.heatProtectionLimitOutOfRange(
                settings.temperatureLimit
            )
        }
    }
}
