import Foundation

enum GoogleCalendarDTO {
    struct ReminderValue: Decodable {
        let method: String
        let minutes: Int
    }

    struct CalendarListPage: Decodable {
        let nextPageToken: String?
        let items: [CalendarListEntry]?
    }

    struct CalendarListEntry: Decodable {
        let id: String
        let summary: String
        let summaryOverride: String?
        let timeZone: String?
        let selected: Bool?
        let primary: Bool?
        let accessRole: String
        let backgroundColor: String?
        let defaultReminders: [ReminderValue]?
        let deleted: Bool?
        let hidden: Bool?
    }

    struct EventPage: Decodable {
        let nextPageToken: String?
        let items: [EventValue]?
    }

    struct EventValue: Decodable {
        struct DateTimeValue: Decodable {
            let date: String?
            let dateTime: String?
            let timeZone: String?
        }

        struct ReminderSettings: Decodable {
            let useDefault: Bool?
            let overrides: [ReminderValue]?
        }

        let id: String
        let status: String?
        let htmlLink: String?
        let summary: String?
        let location: String?
        let start: DateTimeValue?
        let end: DateTimeValue?
        let recurringEventId: String?
        let originalStartTime: DateTimeValue?
        let reminders: ReminderSettings?
    }

    struct ErrorEnvelope: Decodable {
        struct ErrorBody: Decodable {
            struct Detail: Decodable {
                let reason: String?
            }

            let errors: [Detail]?
        }

        let error: ErrorBody
    }
}
