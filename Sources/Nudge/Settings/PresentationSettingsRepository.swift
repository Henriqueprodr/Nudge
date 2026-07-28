@MainActor
protocol PresentationSettingsRepository {
    func fetchSettings() -> PresentationSettings?
    func save(_ settings: PresentationSettings)
}
