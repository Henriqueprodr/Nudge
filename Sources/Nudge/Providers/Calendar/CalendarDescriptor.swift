import Foundation

struct CalendarDescriptor: Codable, Identifiable, Equatable, Sendable {
    struct ReminderRule: Codable, Equatable, Sendable {
        let method: String
        let minutes: Int
    }

    let id: String
    let title: String
    let timeZoneIdentifier: String?
    let isSelectedInGoogleCalendar: Bool
    let isPrimary: Bool
    let defaultReminders: [ReminderRule]
    let backgroundColorHex: String?

    init(
        id: String,
        title: String,
        timeZoneIdentifier: String?,
        isSelectedInGoogleCalendar: Bool,
        isPrimary: Bool,
        defaultReminders: [ReminderRule],
        backgroundColorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isSelectedInGoogleCalendar = isSelectedInGoogleCalendar
        self.isPrimary = isPrimary
        self.defaultReminders = defaultReminders
        self.backgroundColorHex = backgroundColorHex
    }
}
