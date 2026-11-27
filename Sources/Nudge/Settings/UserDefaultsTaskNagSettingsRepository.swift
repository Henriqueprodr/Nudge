import Foundation

@MainActor
final class UserDefaultsTaskNagSettingsRepository: TaskNagSettingsRepository {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "taskNagSettings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func fetchSettings() -> TaskNagSettings? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TaskNagSettings.self, from: data)
    }

    func save(_ settings: TaskNagSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: key)
    }
}
