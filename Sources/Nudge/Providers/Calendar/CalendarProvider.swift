import Foundation

@MainActor
protocol GoogleCalendarProviding: AnyObject {
    func fetchCalendars(accessToken: String) async throws -> [CalendarDescriptor]
    func fetchEvents(
        calendar: CalendarDescriptor,
        in interval: DateInterval,
        accessToken: String
    ) async throws -> [CalendarEventSnapshot]
}
