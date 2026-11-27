import Foundation

/// Local memory about one task, used only to pace nags. Never sent to Google.
struct TaskNagObservation: Codable, Equatable, Sendable {
    /// When Nudge first saw the task. Google Tasks exposes no creation date.
    var firstSeenAt: Date
    var lastNaggedAt: Date?
    var nagCount: Int = 0
    /// Set by Snooze: nag again no earlier than this.
    var snoozedUntil: Date?
    /// Set by "Not today": no nags until this date.
    var silencedUntil: Date?
}
