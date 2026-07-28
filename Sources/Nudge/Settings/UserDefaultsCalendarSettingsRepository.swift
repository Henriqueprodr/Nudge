import Foundation

@MainActor
final class UserDefaultsCalendarSettingsRepository: CalendarSettingsRepository {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "calendarSettings"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func fetchSettings() -> CalendarSettings? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(CalendarSettings.self, from: data)
    }

    func save(_ settings: CalendarSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
