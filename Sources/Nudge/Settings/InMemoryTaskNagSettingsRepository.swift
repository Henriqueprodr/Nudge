/// Volatile nag settings for screenshot captures and hosted tests.
@MainActor
final class InMemoryTaskNagSettingsRepository: TaskNagSettingsRepository {
    private var settings: TaskNagSettings?

    func fetchSettings() -> TaskNagSettings? {
        settings
    }

    func save(_ settings: TaskNagSettings) {
        self.settings = settings
    }
}
