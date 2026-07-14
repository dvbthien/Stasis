import Foundation
import os.log

actor ChargingSettingsStore {
    private static let loadLogger = Logger(
        subsystem: "com.srimanachanta.stasis-daemon",
        category: "ChargingSettingsStore"
    )
    private enum Key {
        static let managementEnabled = "charging.management.isEnabled"
        static let chargeLimit = "charging.threshold.chargeLimit"
        static let sailingModeEnabled = "charging.threshold.sailingModeEnabled"
        static let sailingDelta = "charging.threshold.sailingDelta"
        static let automaticDischargeEnabled = "charging.automaticDischarge.isEnabled"
        static let sleepPreventionEnabled = "charging.sleepPrevention.isEnabled"
        static let heatProtectionEnabled = "charging.heatProtection.isEnabled"
        static let heatProtectionLimit = "charging.heatProtection.temperatureLimit"
        static let magSafeLEDEnabled = "charging.magSafeLED.isEnabled"
        static let magSafeLEDHeatState = "charging.magSafeLED.heatProtectionState"
        static let useHardwarePercentage = "charging.batteryPercentage.useHardwarePercentage"
    }

    private let persistence: any ChargingSettingsPersisting
    private let logger = Logger(
        subsystem: "com.srimanachanta.stasis-daemon",
        category: "ChargingSettingsStore"
    )

    private var management: ChargingManagementSettings
    private var threshold: ChargingThresholdSettings
    private var automaticDischarge: AutomaticDischargeSettings
    private var sleepPrevention: SleepPreventionSettings
    private var heatProtection: HeatProtectionSettings
    private var magSafeLED: MagSafeLEDSettings
    private var batteryPercentage: BatteryPercentageSettings

    init(persistence: any ChargingSettingsPersisting) {
        self.persistence = persistence

        management = Self.loadChargingManagementSettings(from: persistence)
        threshold = Self.loadChargingThresholdSettings(from: persistence)
        automaticDischarge = Self.loadAutomaticDischargeSettings(from: persistence)
        sleepPrevention = Self.loadSleepPreventionSettings(from: persistence)
        heatProtection = Self.loadHeatProtectionSettings(from: persistence)
        magSafeLED = Self.loadMagSafeLEDSettings(from: persistence)
        batteryPercentage = Self.loadBatteryPercentageSettings(from: persistence)
    }

    func chargingManagementSettings() -> ChargingManagementSettings { management }
    func chargingThresholdSettings() -> ChargingThresholdSettings { threshold }
    func automaticDischargeSettings() -> AutomaticDischargeSettings { automaticDischarge }
    func sleepPreventionSettings() -> SleepPreventionSettings { sleepPrevention }
    func heatProtectionSettings() -> HeatProtectionSettings { heatProtection }
    func magSafeLEDSettings() -> MagSafeLEDSettings { magSafeLED }
    func batteryPercentageSettings() -> BatteryPercentageSettings { batteryPercentage }

    func setChargingManagementSettings(
        _ settings: ChargingManagementSettings
    ) -> ChargingManagementSettings {
        persistValue(settings.isEnabled, key: Key.managementEnabled)
        management = settings
        return settings
    }

    func setChargingThresholdSettings(
        _ settings: ChargingThresholdSettings
    ) throws -> ChargingThresholdSettings {
        try ChargingSettingsValidation.validate(settings)
        persistValue(settings.chargeLimit, key: Key.chargeLimit)
        persistValue(settings.sailingModeEnabled, key: Key.sailingModeEnabled)
        persistValue(settings.sailingDelta, key: Key.sailingDelta)
        threshold = settings
        return settings
    }

    func setAutomaticDischargeSettings(
        _ settings: AutomaticDischargeSettings
    ) -> AutomaticDischargeSettings {
        persistValue(settings.isEnabled, key: Key.automaticDischargeEnabled)
        automaticDischarge = settings
        return settings
    }

    func setSleepPreventionSettings(
        _ settings: SleepPreventionSettings
    ) -> SleepPreventionSettings {
        persistValue(settings.isEnabled, key: Key.sleepPreventionEnabled)
        sleepPrevention = settings
        return settings
    }

    func setHeatProtectionSettings(
        _ settings: HeatProtectionSettings
    ) throws -> HeatProtectionSettings {
        try ChargingSettingsValidation.validate(settings)
        persistValue(settings.isEnabled, key: Key.heatProtectionEnabled)
        persistValue(settings.temperatureLimit, key: Key.heatProtectionLimit)
        heatProtection = settings
        return settings
    }

    func setMagSafeLEDSettings(_ settings: MagSafeLEDSettings) -> MagSafeLEDSettings {
        persistValue(settings.isEnabled, key: Key.magSafeLEDEnabled)
        persistValue(settings.heatProtectionState, key: Key.magSafeLEDHeatState)
        magSafeLED = settings
        return settings
    }

    func setBatteryPercentageSettings(
        _ settings: BatteryPercentageSettings
    ) -> BatteryPercentageSettings {
        persistValue(settings.useHardwarePercentage, key: Key.useHardwarePercentage)
        batteryPercentage = settings
        return settings
    }

    func makePolicyInput(chargeLimitOverrideActive: Bool) -> ChargingPolicyInput {
        ChargingPolicyInput(
            threshold: threshold,
            automaticDischarge: automaticDischarge,
            sleepPrevention: sleepPrevention,
            heatProtection: heatProtection,
            magSafeLED: magSafeLED,
            batteryPercentage: batteryPercentage,
            chargeLimitOverrideActive: chargeLimitOverrideActive
        )
    }

    private func persistValue<Value: Encodable>(_ value: Value, key: String) {
        do {
            persistence.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("Could not persist setting \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decodePersistedValue<Value: Decodable>(
        _ type: Value.Type,
        key: String,
        from persistence: any ChargingSettingsPersisting
    ) throws -> Value? {
        guard let data = persistence.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func loadChargingManagementSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> ChargingManagementSettings {
        do {
            return ChargingManagementSettings(
                isEnabled: try decodePersistedValue(Bool.self, key: Key.managementEnabled, from: persistence) ?? false
            )
        } catch {
            loadLogger.error("Invalid charging management settings; resetting that group")
            persistence.removeObject(forKey: Key.managementEnabled)
            return ChargingManagementSettings()
        }
    }

    private static func loadChargingThresholdSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> ChargingThresholdSettings {
        do {
            let settings = ChargingThresholdSettings(
                chargeLimit: try decodePersistedValue(Int.self, key: Key.chargeLimit, from: persistence) ?? 80,
                sailingModeEnabled: try decodePersistedValue(Bool.self, key: Key.sailingModeEnabled, from: persistence) ?? true,
                sailingDelta: try decodePersistedValue(Int.self, key: Key.sailingDelta, from: persistence) ?? 5
            )
            try ChargingSettingsValidation.validate(settings)
            return settings
        } catch {
            loadLogger.error("Invalid charging threshold settings; resetting that group")
            [Key.chargeLimit, Key.sailingModeEnabled, Key.sailingDelta].forEach {
                persistence.removeObject(forKey: $0)
            }
            return ChargingThresholdSettings()
        }
    }

    private static func loadAutomaticDischargeSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> AutomaticDischargeSettings {
        do {
            return AutomaticDischargeSettings(
                isEnabled: try decodePersistedValue(Bool.self, key: Key.automaticDischargeEnabled, from: persistence) ?? true
            )
        } catch {
            loadLogger.error("Invalid automatic discharge settings; resetting that group")
            persistence.removeObject(forKey: Key.automaticDischargeEnabled)
            return AutomaticDischargeSettings()
        }
    }

    private static func loadSleepPreventionSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> SleepPreventionSettings {
        do {
            return SleepPreventionSettings(
                isEnabled: try decodePersistedValue(Bool.self, key: Key.sleepPreventionEnabled, from: persistence) ?? false
            )
        } catch {
            loadLogger.error("Invalid sleep prevention settings; resetting that group")
            persistence.removeObject(forKey: Key.sleepPreventionEnabled)
            return SleepPreventionSettings()
        }
    }

    private static func loadHeatProtectionSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> HeatProtectionSettings {
        do {
            let settings = HeatProtectionSettings(
                isEnabled: try decodePersistedValue(Bool.self, key: Key.heatProtectionEnabled, from: persistence) ?? true,
                temperatureLimit: try decodePersistedValue(Int.self, key: Key.heatProtectionLimit, from: persistence) ?? 40
            )
            try ChargingSettingsValidation.validate(settings)
            return settings
        } catch {
            loadLogger.error("Invalid heat protection settings; resetting that group")
            [Key.heatProtectionEnabled, Key.heatProtectionLimit].forEach {
                persistence.removeObject(forKey: $0)
            }
            return HeatProtectionSettings()
        }
    }

    private static func loadMagSafeLEDSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> MagSafeLEDSettings {
        do {
            return MagSafeLEDSettings(
                isEnabled: try decodePersistedValue(Bool.self, key: Key.magSafeLEDEnabled, from: persistence) ?? true,
                heatProtectionState: try decodePersistedValue(MagSafeLEDState.self, key: Key.magSafeLEDHeatState, from: persistence) ?? .blinkOrangeSlow
            )
        } catch {
            loadLogger.error("Invalid MagSafe LED settings; resetting that group")
            [Key.magSafeLEDEnabled, Key.magSafeLEDHeatState].forEach {
                persistence.removeObject(forKey: $0)
            }
            return MagSafeLEDSettings()
        }
    }

    private static func loadBatteryPercentageSettings(
        from persistence: any ChargingSettingsPersisting
    ) -> BatteryPercentageSettings {
        do {
            return BatteryPercentageSettings(
                useHardwarePercentage: try decodePersistedValue(Bool.self, key: Key.useHardwarePercentage, from: persistence) ?? false
            )
        } catch {
            loadLogger.error("Invalid battery percentage settings; resetting that group")
            persistence.removeObject(forKey: Key.useHardwarePercentage)
            return BatteryPercentageSettings()
        }
    }
}
