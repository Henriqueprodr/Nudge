import Foundation

/// The exact strings the reminder control strip renders.
///
/// The value is built once per presentation so the strip never animates, ticks, or recomputes a
/// countdown while it is on screen. Every input needed for formatting is injected so the mapping
/// is deterministic in tests.
struct ReminderStripPresentation: Equatable, Sendable {
    /// Fallback accent used when the source calendar exposes no colour.
    static let fallbackAccentHex = NudgePalette.blueHex

    let eyebrow: String
    let timeText: String
    let dateText: String
    let title: String
    let metadata: String?
    let accentHex: String
    let hasSource: Bool

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
