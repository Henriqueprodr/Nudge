import Foundation

@MainActor
protocol CalendarReminderConsumer: AnyObject {
    func replaceCalendarReminders(with reminders: [Reminder]) throws
}
