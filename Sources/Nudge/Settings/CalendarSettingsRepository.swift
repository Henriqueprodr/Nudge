import Foundation

@MainActor
protocol CalendarSettingsRepository {
    func fetchSettings() -> CalendarSettings?
    func save(_ settings: CalendarSettings)
}
