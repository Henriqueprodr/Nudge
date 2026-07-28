import Foundation

@MainActor
final class UserDefaultsGoogleTasksSettingsRepository: GoogleTasksSettingsRepository {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "googleTasksSettings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func fetchSettings() -> GoogleTasksSettings? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleTasksSettings.self, from: data)
    }

    func save(_ settings: GoogleTasksSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
