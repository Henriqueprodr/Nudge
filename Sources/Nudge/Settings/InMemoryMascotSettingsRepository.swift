/// Volatile mascot settings for screenshot captures and hosted tests.
@MainActor
final class InMemoryMascotSettingsRepository: MascotSettingsRepository {
    private var settings: MascotSettings?

    func fetchSettings() -> MascotSettings? {
        settings
    }

    func save(_ settings: MascotSettings) {
        self.settings = settings
    }
}
