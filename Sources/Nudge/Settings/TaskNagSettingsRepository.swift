@MainActor
protocol TaskNagSettingsRepository {
    func fetchSettings() -> TaskNagSettings?
    func save(_ settings: TaskNagSettings)
}
