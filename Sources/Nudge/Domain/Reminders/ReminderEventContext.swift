import Foundation

/// Provider-neutral event facts the reminder surface presents alongside the title.
///
/// Every member is optional except the scheduled start because reminders may originate from
/// sources that do not expose a calendar, a location, or a colour. Optional members also let
/// previously cached JSON payloads decode without a persistence migration.
struct ReminderEventContext: Codable, Hashable, Sendable {
    let startDate: Date
    let calendarTitle: String?
    let location: String?
    let calendarColorHex: String?
    /// `true` for date-only calendar events. Optional so reminders restored from older encoded
    /// payloads remain compatible without a persistence migration.
    let isAllDay: Bool?

    init(
        startDate: Date,
        calendarTitle: String? = nil,
        location: String? = nil,
        calendarColorHex: String? = nil,
        isAllDay: Bool? = nil
    ) {
        self.startDate = startDate
        self.calendarTitle = calendarTitle
        self.location = location
        self.calendarColorHex = calendarColorHex
        self.isAllDay = isAllDay
    }
}
