import Foundation

struct GoogleCalendarMapper: Sendable {
    private static let maximumReminderMinutes = 40_320

    func calendar(from value: GoogleCalendarDTO.CalendarListEntry) -> CalendarDescriptor? {
        guard
            value.deleted != true,
            value.hidden != true,
            ["reader", "writer", "owner"].contains(value.accessRole)
        else {
            return nil
        }
        return CalendarDescriptor(
            id: value.id,
            title: value.summaryOverride ?? value.summary,
            timeZoneIdentifier: value.timeZone,
            isSelectedInGoogleCalendar: value.selected == true,
            isPrimary: value.primary == true,
            defaultReminders: (value.defaultReminders ?? []).map {
                CalendarDescriptor.ReminderRule(method: $0.method, minutes: $0.minutes)
            },
            backgroundColorHex: value.backgroundColor
        )
    }

    func event(
        from value: GoogleCalendarDTO.EventValue,
        calendar: CalendarDescriptor
    ) -> CalendarEventSnapshot? {
        guard
            value.status != "cancelled",
            !value.id.isEmpty,
            let startValue = value.start,
            let endValue = value.end,
            let start = parsedDate(from: startValue, calendarTimeZone: calendar.timeZoneIdentifier),
            let end = parsedDate(from: endValue, calendarTimeZone: calendar.timeZoneIdentifier)
        else {
            return nil
        }

        let isAllDay = startValue.date != nil
        let stableValueSource = value.recurringEventId == nil
            ? startValue
            : value.originalStartTime ?? startValue
        guard let stableOccurrenceValue = stableValue(
            from: stableValueSource,
            calendarTimeZone: calendar.timeZoneIdentifier
        ), let stableOccurrenceDate = parsedDate(
            from: stableValueSource,
            calendarTimeZone: calendar.timeZoneIdentifier
        )?.date else {
            return nil
        }

        let rawReminders: [GoogleCalendarDTO.ReminderValue]
        if value.reminders?.useDefault == true {
            rawReminders = calendar.defaultReminders.map {
                GoogleCalendarDTO.ReminderValue(method: $0.method, minutes: $0.minutes)
            }
        } else if value.reminders?.useDefault == false {
            rawReminders = value.reminders?.overrides ?? []
        } else {
            rawReminders = []
        }

        let supported = rawReminders
            .filter { $0.method == "popup" && (0...Self.maximumReminderMinutes).contains($0.minutes) }
            .sorted {
                ($0.method, $0.minutes) < ($1.method, $1.minutes)
            }
        var duplicateCounts: [String: Int] = [:]
        let reminders = supported.map { reminder in
            let key = "\(reminder.method)|\(reminder.minutes)"
            let ordinal = duplicateCounts[key, default: 0]
            duplicateCounts[key] = ordinal + 1
            return CalendarEventSnapshot.ReminderRule(
                method: reminder.method,
                minutes: reminder.minutes,
                duplicateOrdinal: ordinal
            )
        }

        return CalendarEventSnapshot(
            eventIdentifier: value.id,
            recurringEventIdentifier: value.recurringEventId,
            stableOccurrenceValue: stableOccurrenceValue,
            stableOccurrenceDate: stableOccurrenceDate,
            calendarIdentifier: calendar.id,
            calendarTitle: calendar.title,
            calendarColorHex: calendar.backgroundColorHex,
            title: value.summary ?? "",
            location: value.location,
            startDate: start.date,
            endDate: end.date,
            isAllDay: isAllDay,
            timeZoneIdentifier: start.timeZoneIdentifier,
            reminders: reminders,
            sourceURL: GoogleCalendarLinkValidator.validatedURL(from: value.htmlLink)
        )
    }

    private func stableValue(
        from value: GoogleCalendarDTO.EventValue.DateTimeValue,
        calendarTimeZone: String?
    ) -> String? {
        guard let parsed = parsedDate(from: value, calendarTimeZone: calendarTimeZone) else {
            return nil
        }
        return value.date != nil
            ? "date:\(value.date!)|\(parsed.timeZoneIdentifier)"
            : "time:\(parsed.date.timeIntervalSince1970)"
    }

    private func parsedDate(
        from value: GoogleCalendarDTO.EventValue.DateTimeValue,
        calendarTimeZone: String?
    ) -> (date: Date, timeZoneIdentifier: String)? {
        if let dateTime = value.dateTime {
            let timeZone = value.timeZone.flatMap(TimeZone.init(identifier:))
                ?? calendarTimeZone.flatMap(TimeZone.init(identifier:))
                ?? .current
            if let date = Self.rfc3339Date(dateTime)
                ?? Self.localDateTime(dateTime, timeZone: timeZone) {
                return (date, timeZone.identifier)
            }
        }
        guard let dateOnly = value.date else { return nil }
        let timeZone = value.timeZone.flatMap(TimeZone.init(identifier:))
            ?? calendarTimeZone.flatMap(TimeZone.init(identifier:))
            ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = dateOnly.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        let values = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: components[0],
            month: components[1],
            day: components[2]
        )
        guard let date = calendar.date(from: values) else { return nil }
        let validation = calendar.dateComponents([.year, .month, .day], from: date)
        guard validation.year == components[0],
              validation.month == components[1],
              validation.day == components[2] else { return nil }
        return (date, timeZone.identifier)
    }

    private static func rfc3339Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func localDateTime(_ value: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
