import Foundation

struct CalendarEventSnapshot: Codable, Equatable, Sendable {
    struct ReminderRule: Codable, Equatable, Sendable {
        let method: String
        let minutes: Int
        let duplicateOrdinal: Int
    }

    let eventIdentifier: String
    let recurringEventIdentifier: String?
    let stableOccurrenceValue: String
    let stableOccurrenceDate: Date
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String?
    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let reminders: [ReminderRule]
    let sourceURL: URL?
}
