import Foundation

struct CalendarReminderMapper {
    func reminders(from snapshot: CalendarEventSnapshot) -> [Reminder] {
        snapshot.reminders.map { rule in
            let triggerDate = snapshot.startDate.addingTimeInterval(
                -TimeInterval(rule.minutes * 60)
            )
            return Reminder(
                occurrenceID: ReminderOccurrenceID(
                    sourceKind: .calendar,
                    sourceIdentifier: [
                        snapshot.calendarIdentifier,
                        snapshot.recurringEventIdentifier ?? snapshot.eventIdentifier,
                        snapshot.stableOccurrenceValue,
                        rule.method,
                        String(rule.minutes),
                        String(rule.duplicateOrdinal),
                    ].joined(separator: "|"),
                    occurrenceDate: snapshot.stableOccurrenceDate,
                    revision: nil
                ),
                title: snapshot.title.isEmpty ? "Calendar event" : snapshot.title,
                detail: detail(for: snapshot),
                triggerDate: triggerDate,
                expirationDate: triggerDate.addingTimeInterval(15 * 60),
                presentationMode: .overlay,
                sourceURL: snapshot.sourceURL,
                eventContext: eventContext(for: snapshot)
            )
        }
    }

    private func detail(for snapshot: CalendarEventSnapshot) -> String {
        var components = [snapshot.calendarTitle]
        if let location = trimmed(snapshot.location) {
            components.append(location)
        }
        return components.joined(separator: " · ")
    }

    private func eventContext(for snapshot: CalendarEventSnapshot) -> ReminderEventContext {
        ReminderEventContext(
            startDate: snapshot.startDate,
            calendarTitle: trimmed(snapshot.calendarTitle),
            location: trimmed(snapshot.location),
            calendarColorHex: trimmed(snapshot.calendarColorHex),
            isAllDay: snapshot.isAllDay
        )
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
