import Foundation

@MainActor
final class UserDefaultsPresentationSettingsRepository: PresentationSettingsRepository {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults = .standard, key: String = "presentationSettings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    func fetchSettings() -> PresentationSettings? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(PresentationSettings.self, from: data)
    }

    func save(_ settings: PresentationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
