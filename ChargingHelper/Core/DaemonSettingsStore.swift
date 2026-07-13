import Foundation

private struct DaemonSettingsRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var settings: DaemonSettings
    var revision: UInt64
    var didImportLegacyAppSettings: Bool
}

actor DaemonSettingsStore {
    private let persistence: any DaemonSettingsPersisting
    private let validator: DaemonSettingsValidator
    private var record: DaemonSettingsRecord

    init(
        persistence: any DaemonSettingsPersisting,
        capabilities: DaemonCapabilities
    ) throws {
        self.persistence = persistence
        let validator = DaemonSettingsValidator(capabilities: capabilities)
        self.validator = validator

        if let data = try persistence.load() {
            let decoded = try JSONDecoder().decode(DaemonSettingsRecord.self, from: data)
            guard decoded.schemaVersion == DaemonSettingsRecord.currentSchemaVersion else {
                throw DaemonSettingsValidationError.incompatibleSchema(
                    expected: DaemonSettingsRecord.currentSchemaVersion,
                    actual: decoded.schemaVersion
                )
            }

            let normalized = try validator.validateAndNormalize(decoded.settings)
            if normalized == decoded.settings {
                record = decoded
            } else {
                var updated = decoded
                updated.settings = normalized
                updated.revision += 1
                record = updated
                try Self.persist(updated, using: persistence)
            }
        } else {
            let settings = try validator.validateAndNormalize(DaemonSettings())
            let initial = DaemonSettingsRecord(
                settings: settings,
                revision: 0,
                didImportLegacyAppSettings: false
            )
            record = initial
            try Self.persist(initial, using: persistence)
        }
    }

    func state() -> DaemonSettingsState {
        DaemonSettingsState(
            settings: record.settings,
            revision: record.revision,
            needsLegacyImport: !record.didImportLegacyAppSettings
        )
    }

    func setSettings(_ settings: DaemonSettings) throws -> DaemonSettingsState {
        let normalized = try validator.validateAndNormalize(settings)
        var updated = record
        updated.settings = normalized
        updated.revision += 1
        updated.didImportLegacyAppSettings = true
        try Self.persist(updated, using: persistence)
        record = updated
        return state()
    }

    func importLegacySettings(_ settings: DaemonSettings) throws -> DaemonSettingsState {
        guard !record.didImportLegacyAppSettings else { return state() }
        return try setSettings(settings)
    }

    private static func persist(
        _ record: DaemonSettingsRecord,
        using persistence: any DaemonSettingsPersisting
    ) throws {
        try persistence.save(JSONEncoder().encode(record))
    }
}
