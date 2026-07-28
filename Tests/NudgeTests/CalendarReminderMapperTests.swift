import Foundation
import XCTest
@testable import Nudge

final class CalendarReminderMapperTests: XCTestCase {
    func testResolvedPopupRemindersHaveDistinctStableIdentities() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-25T15:00:00Z"))
        let snapshot = makeSnapshot(
            startDate: start,
            reminders: [
                .init(method: "popup", minutes: 10, duplicateOrdinal: 0),
                .init(method: "popup", minutes: 10, duplicateOrdinal: 1),
            ]
        )

        let reminders = CalendarReminderMapper().reminders(from: snapshot)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertNotEqual(reminders[0].occurrenceID, reminders[1].occurrenceID)
        XCTAssertEqual(reminders.map(\.triggerDate), [
            start.addingTimeInterval(-600),
            start.addingTimeInterval(-600),
        ])
        XCTAssertTrue(reminders.allSatisfy { $0.presentationMode == .overlay })
    }

    func testRecurringMovedInstancesUseImmutableOriginalStartIdentity() throws {
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-25T15:00:00Z"))
        let moved = first.addingTimeInterval(3_600)
        let mapper = CalendarReminderMapper()

        let originalReminder = try XCTUnwrap(mapper.reminders(from: makeSnapshot(
            startDate: first,
            stableOccurrenceValue: "time:100",
            reminders: [.init(method: "popup", minutes: 5, duplicateOrdinal: 0)]
        )).first)
        let movedReminder = try XCTUnwrap(mapper.reminders(from: makeSnapshot(
            startDate: moved,
            stableOccurrenceValue: "time:100",
            reminders: [.init(method: "popup", minutes: 5, duplicateOrdinal: 0)]
        )).first)

        XCTAssertEqual(originalReminder.occurrenceID.sourceIdentifier, movedReminder.occurrenceID.sourceIdentifier)
        XCTAssertEqual(originalReminder.occurrenceID, movedReminder.occurrenceID)
        XCTAssertNotEqual(originalReminder.triggerDate, movedReminder.triggerDate)
    }

    func testMapperPreservesOnlyValidatedProviderLink() {
        XCTAssertNotNil(GoogleCalendarLinkValidator.validatedURL(
            from: "https://calendar.google.com/calendar/event?eid=opaque"
        ))
        XCTAssertNotNil(GoogleCalendarLinkValidator.validatedURL(
            from: "https://www.google.com/calendar/event?eid=opaque"
        ))
        XCTAssertNil(GoogleCalendarLinkValidator.validatedURL(
            from: "http://calendar.google.com/calendar/event"
        ))
        XCTAssertNil(GoogleCalendarLinkValidator.validatedURL(
            from: "https://user:pass@calendar.google.com/calendar/event"
        ))
        XCTAssertNil(GoogleCalendarLinkValidator.validatedURL(
            from: "https://example.com/calendar/event"
        ))
        XCTAssertNil(GoogleCalendarLinkValidator.validatedURL(
            from: "https://www.google.com/search?q=calendar"
        ))
    }

    @MainActor
    func testSourceOpenerPreservesExactValidatedProviderLink() throws {
        let expectedURL = try XCTUnwrap(URL(
            string: "https://calendar.google.com/calendar/event?eid=opaque&authuser=1"
        ))
        let browser = RecordingCalendarBrowserOpener()
        let opener = ReminderSourceOpener(browserOpener: browser)
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: "opaque-identity",
                occurrenceDate: Date(timeIntervalSince1970: 100),
                revision: nil
            ),
            title: "Event",
            detail: nil,
            triggerDate: Date(timeIntervalSince1970: 200),
            expirationDate: nil,
            presentationMode: .overlay,
            sourceURL: expectedURL
        )

        XCTAssertTrue(opener.openSource(for: reminder))
        XCTAssertEqual(browser.openedURLs, [expectedURL])
    }

    private func makeSnapshot(
        startDate: Date,
        stableOccurrenceValue: String = "time:100",
        reminders: [CalendarEventSnapshot.ReminderRule]
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            eventIdentifier: "event",
            recurringEventIdentifier: "series",
            stableOccurrenceValue: stableOccurrenceValue,
            stableOccurrenceDate: Date(timeIntervalSince1970: 100),
            calendarIdentifier: "calendar",
            calendarTitle: "Calendar",
            calendarColorHex: "#3f51b5",
            title: "Event",
            location: nil,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            reminders: reminders,
            sourceURL: URL(string: "https://calendar.google.com/calendar/event?eid=opaque")
        )
    }
}

@MainActor
private final class RecordingCalendarBrowserOpener: SystemBrowserOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}
