import Foundation

@MainActor
final class UserDefaultsMascotSettingsRepository: MascotSettingsRepository {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "mascotSettings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func fetchSettings() -> MascotSettings? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MascotSettings.self, from: data)
    }

    func save(_ settings: MascotSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: key)
    }
}
