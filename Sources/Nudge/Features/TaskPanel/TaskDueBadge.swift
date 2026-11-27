import Foundation

/// The small chip beside a task: "today", "tomorrow", or "3d late".
struct TaskDueBadge: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case late
        case today
        case upcoming
    }

    let text: String
    let kind: Kind

    /// `nil` for undated tasks and tasks due more than a day away.
    init?(dueDate: TaskItem.DueDate?, now: Date, calendar: Calendar = .current) {
        guard let dueDate,
              let dueDay = calendar.date(
                  from: DateComponents(year: dueDate.year, month: dueDate.month, day: dueDate.day)
              ) else {
            return nil
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: dueDay)
        ).day ?? 0
        switch days {
        case ..<0:
            text = "\(-days)d late"
            kind = .late
        case 0:
            text = "today"
            kind = .today
        case 1:
            text = "tomorrow"
            kind = .upcoming
        default:
            return nil
        }
    }
}
