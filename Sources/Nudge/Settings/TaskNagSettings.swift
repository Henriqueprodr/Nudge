import Foundation

/// How Nudge nags about unfinished Google Tasks. There is no per-task configuration: cadence
/// comes from each task's due date, age, and priority (see `TaskNagPolicy`).
struct TaskNagSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    /// Hour (0–23) when quiet hours begin. No nags from here until `quietHoursEndHour`.
    var quietHoursStartHour: Int
    /// Hour (0–23) when quiet hours end and nagging may resume.
    var quietHoursEndHour: Int
    /// Most nag alerts per calendar day.
    var dailyLimit: Int
    /// Shortest time between two nag alerts, in minutes.
    var minimumGapMinutes: Int
    /// Whether tasks without a due date are nagged once they have been open for a few days.
    var includesUndatedTasks: Bool

    static let defaultValue = TaskNagSettings(
        isEnabled: true,
        quietHoursStartHour: 22,
        quietHoursEndHour: 9,
        dailyLimit: 6,
        minimumGapMinutes: 45,
        includesUndatedTasks: true
    )

    static let dailyLimitRange = 1...20
    static let minimumGapRange = 15...240

    /// Clamps every field into its documented range.
    var validated: TaskNagSettings {
        var copy = self
        copy.quietHoursStartHour = min(max(quietHoursStartHour, 0), 23)
        copy.quietHoursEndHour = min(max(quietHoursEndHour, 0), 23)
        copy.dailyLimit = min(max(dailyLimit, Self.dailyLimitRange.lowerBound), Self.dailyLimitRange.upperBound)
        copy.minimumGapMinutes = min(
            max(minimumGapMinutes, Self.minimumGapRange.lowerBound),
            Self.minimumGapRange.upperBound
        )
        return copy
    }
}
