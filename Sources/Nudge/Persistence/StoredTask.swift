import Foundation
import SwiftData

@Model
final class StoredTask {
    @Attribute(.unique) var identifier: String
    var taskListIdentifier: String
    var title: String
    var notes: String?
    var completionStateRawValue: String
    var dueYear: Int?
    var dueMonth: Int?
    var dueDay: Int?
    var overrideHour: Int?
    var overrideMinute: Int?
    var overrideTimeZoneIdentifier: String?
    var webViewURLString: String?
    var locallySnoozedUntil: Date?
    var priorityRawValue: String = TaskPriority.none.rawValue

    init(task: TaskItem) {
        identifier = task.id
        taskListIdentifier = task.taskListID
        title = task.title
        notes = task.notes
        completionStateRawValue = task.completionState.rawValue
        dueYear = task.dueDate?.year
        dueMonth = task.dueDate?.month
        dueDay = task.dueDate?.day
        overrideHour = task.localTimeOverride?.hour
        overrideMinute = task.localTimeOverride?.minute
        overrideTimeZoneIdentifier = task.localTimeOverride?.timeZoneIdentifier
        webViewURLString = task.webViewURL?.absoluteString
        locallySnoozedUntil = task.locallySnoozedUntil
        priorityRawValue = task.priority.rawValue
    }

    func update(from task: TaskItem) {
        taskListIdentifier = task.taskListID
        title = task.title
        notes = task.notes
        completionStateRawValue = task.completionState.rawValue
        dueYear = task.dueDate?.year
        dueMonth = task.dueDate?.month
        dueDay = task.dueDate?.day
        overrideHour = task.localTimeOverride?.hour
        overrideMinute = task.localTimeOverride?.minute
        overrideTimeZoneIdentifier = task.localTimeOverride?.timeZoneIdentifier
        webViewURLString = task.webViewURL?.absoluteString
        locallySnoozedUntil = task.locallySnoozedUntil
        priorityRawValue = task.priority.rawValue
    }

    func domainValue() -> TaskItem? {
        guard let completionState = TaskItem.CompletionState(rawValue: completionStateRawValue) else {
            return nil
        }

        let dueDate: TaskItem.DueDate?
        if let dueYear, let dueMonth, let dueDay {
            dueDate = TaskItem.DueDate(year: dueYear, month: dueMonth, day: dueDay)
        } else {
            dueDate = nil
        }

        let localTimeOverride: TaskItem.LocalTimeOverride?
        if let overrideHour, let overrideMinute, let overrideTimeZoneIdentifier {
            localTimeOverride = TaskItem.LocalTimeOverride(
                hour: overrideHour,
                minute: overrideMinute,
                timeZoneIdentifier: overrideTimeZoneIdentifier
            )
        } else {
            localTimeOverride = nil
        }

        return TaskItem(
            id: identifier,
            taskListID: taskListIdentifier,
            title: title,
            notes: notes,
            completionState: completionState,
            dueDate: dueDate,
            localTimeOverride: localTimeOverride,
            webViewURL: webViewURLString.flatMap(URL.init(string:)),
            locallySnoozedUntil: locallySnoozedUntil,
            priority: TaskPriority(rawValue: priorityRawValue) ?? .none
        )
    }
}
