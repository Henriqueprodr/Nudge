@MainActor
protocol MascotSettingsRepository {
    func fetchSettings() -> MascotSettings?
    func save(_ settings: MascotSettings)
}
