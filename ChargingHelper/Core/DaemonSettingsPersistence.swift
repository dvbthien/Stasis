import Foundation

protocol DaemonSettingsPersisting: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct UserDefaultsDaemonSettingsPersistence: DaemonSettingsPersisting, @unchecked Sendable {
    private static let recordKey = "daemonSettingsRecord"

    private let defaults: UserDefaults

    init() {
        defaults = .standard
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() throws -> Data? {
        defaults.data(forKey: Self.recordKey)
    }

    func save(_ data: Data) throws {
        defaults.set(data, forKey: Self.recordKey)
    }
}
