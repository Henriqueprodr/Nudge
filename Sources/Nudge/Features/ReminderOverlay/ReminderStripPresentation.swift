import Foundation

/// The exact strings the reminder control strip renders.
///
/// The value is built once per presentation so the strip never animates, ticks, or recomputes a
/// countdown while it is on screen. Every input needed for formatting is injected so the mapping
/// is deterministic in tests.
struct ReminderStripPresentation: Equatable, Sendable {
    /// Fallback accent used when the source calendar exposes no colour.
    static let fallbackAccentHex = NudgePalette.blueHex

    var eyebrow: String
    var timeText: String
    var dateText: String
    var title: String
    var metadata: String?
    var accentHex: String
    let hasSource: Bool
    /// Source-specific actions shown before Snooze, in order.
    var actions: [ReminderAction] = []
    var snoozeTitle = "Snooze"
    var snoozeAccessibilityLabel = "Snooze reminder for 10 minutes"

    init(
        reminder: Reminder,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        var calendar = calendar
        calendar.locale = locale

        let context = reminder.eventContext
        let referenceDate = context?.startDate ?? reminder.triggerDate
        let isCalendarEvent = reminder.occurrenceID.sourceKind == .calendar

        eyebrow = isCalendarEvent ? "UPCOMING EVENT" : "REMINDER"
        title = reminder.title
        actions = reminder.actions
        hasSource = reminder.sourceURL != nil
        accentHex = context?.calendarColorHex ?? Self.fallbackAccentHex
        timeText = context?.isAllDay == true
            ? "ALL DAY"
            : Self.timeText(for: referenceDate, calendar: calendar, locale: locale)
        dateText = Self.dateText(
            for: referenceDate,
            now: now,
            calendar: calendar,
            locale: locale
        )
        metadata = Self.metadata(for: reminder, referenceDate: referenceDate, now: now)

        if let taskContext = reminder.taskContext {
            applyTaskWording(taskContext, reminder: reminder, calendar: calendar, locale: locale)
        }
    }

    static let taskAccentHex = "#7FBA00"
    static let lateTaskAccentHex = "#D9534F"

    private mutating func applyTaskWording(
        _ context: ReminderTaskContext,
        reminder: Reminder,
        calendar: Calendar,
        locale: Locale
    ) {
        let outstanding = context.taskIDs.count
        eyebrow = outstanding > 1 ? "\(outstanding) TASKS STILL NOT DONE" : "STILL NOT DONE"
        title = context.additionalTaskCount > 0
            ? "\(reminder.title) + \(context.additionalTaskCount) more"
            : reminder.title
        snoozeTitle = "Snooze 1h"
        snoozeAccessibilityLabel = "Snooze task reminder for 1 hour"
        accentHex = context.urgency == .dueToday ? Self.taskAccentHex : Self.lateTaskAccentHex

        switch context.urgency {
        case .dueToday:
            timeText = "TODAY"
        case .overdue, .ancient:
            let days = context.daysOverdue ?? context.daysOpen
            timeText = days == 1 ? "1 DAY" : "\(days) DAYS"
        case .lingering:
            timeText = "\(context.daysOpen) DAYS"
        }

        if let dueDate = context.dueDate,
           let date = calendar.date(
               from: DateComponents(year: dueDate.year, month: dueDate.month, day: dueDate.day)
           ) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
            let dueText = formatter.string(from: date)
            dateText = context.urgency == .dueToday ? "DUE TODAY" : "LATE"
            metadata = Self.dueDateSentence(dueText: dueText, daysOverdue: context.daysOverdue ?? 0)
        } else {
            dateText = "OPEN"
            metadata = context.daysOpen == 1
                ? "Sitting on your list since yesterday"
                : "Sitting on your list for \(context.daysOpen) days"
        }
    }

    private static func dueDateSentence(dueText: String, daysOverdue: Int) -> String {
        switch daysOverdue {
        case ..<1:
            return "You said you'd do it today (\(dueText))"
        case 1:
            return "You said you'd do it \(dueText) · yesterday"
        default:
            return "You said you'd do it \(dueText) · \(daysOverdue) days ago"
        }
    }

    /// Combined label so VoiceOver reads the strip as one coherent reminder.
    var accessibilityLabel: String {
        [eyebrow.capitalized, "\(timeText), \(dateText.lowercased())", title, metadata]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    private static func timeText(
        for date: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static func dateText(
        for date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "TODAY"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "TOMORROW"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "YESTERDAY"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date).uppercased(with: locale)
    }

    private static func metadata(
        for reminder: Reminder,
        referenceDate: Date,
        now: Date
    ) -> String? {
        guard let context = reminder.eventContext else {
            return reminder.detail.flatMap(trimmed)
        }
        let contextualDetail = trimmed(context.calendarTitle) ?? trimmed(context.location)
        let components = [relativeStartText(from: now, to: referenceDate), contextualDetail]
            .compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    /// A single sentence fixed at presentation time; it is never refreshed on a timer.
    private static func relativeStartText(from now: Date, to start: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded())
        switch minutes {
        case 0:
            return "Starts now"
        case 1:
            return "Starts in 1 minute"
        case 2...59:
            return "Starts in \(minutes) minutes"
        case -59 ... -1:
            let elapsed = -minutes
            return elapsed == 1 ? "Started 1 minute ago" : "Started \(elapsed) minutes ago"
        default:
            return startedOrStartsHours(minutes: minutes)
        }
    }

    private static func startedOrStartsHours(minutes: Int) -> String {
        let hours = Int((Double(abs(minutes)) / 60).rounded())
        let unit = hours == 1 ? "hour" : "hours"
        return minutes > 0 ? "Starts in \(hours) \(unit)" : "Started \(hours) \(unit) ago"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
