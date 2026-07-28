import Foundation

struct GoogleTasksMapper: Sendable {
    func taskList(from value: GoogleTasksDTO.TaskListValue) -> TaskList {
        TaskList(id: value.id, title: value.title)
    }

    func task(
        from value: GoogleTasksDTO.TaskValue,
        taskListID: String
    ) -> TaskItem? {
        guard
            value.deleted != true,
            value.hidden != true,
            value.status == "needsAction"
        else {
            return nil
        }
        return TaskItem(
            id: value.id,
            taskListID: taskListID,
            title: value.title,
            notes: value.notes,
            completionState: .incomplete,
            dueDate: value.due.flatMap(Self.dateOnlyDueDate(from:)),
            localTimeOverride: nil,
            webViewURL: value.webViewLink.flatMap(URL.init(string:))
        )
    }

    static func dateOnlyDueDate(from value: String) -> TaskItem.DueDate? {
        let datePortion = value.prefix(10)
        let parts = datePortion.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year, validated.month == month, validated.day == day else {
            return nil
        }
        return TaskItem.DueDate(year: year, month: month, day: day)
    }
}
