import Foundation

/// Extra, source-specific actions a reminder can offer beyond Open, Snooze, and Dismiss.
///
/// The cases are provider-neutral: the app layer routes them to Google Tasks.
enum ReminderAction: String, Codable, Hashable, Sendable {
    /// Mark the reminder's primary task complete.
    case completeTask
    /// Stop nagging about the reminder's tasks until tomorrow.
    case notToday

    var title: String {
        switch self {
        case .completeTask:
            return "Done"
        case .notToday:
            return "Not today"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .completeTask:
            return "Mark task complete"
        case .notToday:
            return "Stop reminding about this task until tomorrow"
        }
    }
}
