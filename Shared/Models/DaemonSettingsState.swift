import Foundation

/// Canonical daemon settings plus synchronization metadata.
struct DaemonSettingsState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var settings: DaemonSettings
    var revision: UInt64
    var needsLegacyImport: Bool
}
