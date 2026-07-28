@MainActor
protocol GoogleTasksSettingsRepository {
    func fetchSettings() -> GoogleTasksSettings?
    func save(_ settings: GoogleTasksSettings)
}
