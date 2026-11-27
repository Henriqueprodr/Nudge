import Foundation

/// Task details carried by a task nag so the overlay and mascot can phrase it.
struct ReminderTaskContext: Codable, Hashable, Sendable {
    enum Urgency: String, Codable, Hashable, Sendable {
        /// Due today and still open.
        case dueToday
        /// Past its due date.
        case overdue
        /// More than a week past its due date, or undated and open for a long time.
        case ancient
        /// No due date, open for several days.
        case lingering
    }

    /// Every task in this nag, most urgent first.
    let taskIDs: [String]
    let primaryTaskListID: String
    let urgency: Urgency
    /// The due date the user picked for the primary task, if any.
    let dueDate: TaskItem.DueDate?
    /// Whole days past the due date; zero when due today, `nil` for undated tasks.
    let daysOverdue: Int?
    /// Whole days since Nudge first saw the primary task.
    let daysOpen: Int

    var primaryTaskID: String? {
        taskIDs.first
    }

    var additionalTaskCount: Int {
        max(taskIDs.count - 1, 0)
    }
}
