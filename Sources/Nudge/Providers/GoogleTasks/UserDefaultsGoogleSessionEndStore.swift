import Foundation

/// Stores only dates, never tokens or account details, so UserDefaults is appropriate.
@MainActor
final class UserDefaultsGoogleSessionEndStore: GoogleSessionEndStore {
    static let defaultsKey = "googleOAuth.lastSessionEnd"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRecord() -> GoogleSessionEndRecord? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? decoder.decode(GoogleSessionEndRecord.self, from: data)
    }

    func saveRecord(_ record: GoogleSessionEndRecord) {
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func clearRecord() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
