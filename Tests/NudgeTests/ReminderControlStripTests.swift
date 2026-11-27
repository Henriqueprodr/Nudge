import AppKit
import SwiftUI
import XCTest
@testable import Nudge

final class ReminderControlStripTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private var locale: Locale { Locale(identifier: "en_US") }

    func testHandDrawnStripUsesApprovedSizingTokens() {
        XCTAssertEqual(ReminderStripStyle.horizontalPadding, 14)
        XCTAssertEqual(ReminderStripStyle.verticalPadding, 12)
        XCTAssertEqual(ReminderStripStyle.regionSpacing, 14)
        XCTAssertEqual(ReminderStripStyle.lineSpacing, 3)
        XCTAssertEqual(ReminderStripStyle.actionSpacing, 8)
        XCTAssertEqual(ReminderStripStyle.timeChipMinimumWidth, 78)
        XCTAssertEqual(ReminderStripStyle.screenTopInset, 44)
        XCTAssertEqual(ReminderStripStyle.minimumWidth, 450)
        XCTAssertEqual(ReminderStripStyle.maximumWidth, 700)
    }

    func testCalendarEventShowsTimeTodayLabelAndConciseMetadata() {
        let presentation = makePresentation(
            startOffset: 10 * 60,
            calendarTitle: "Work Calendar",
            location: "Room 4"
        )

        XCTAssertEqual(presentation.eyebrow, "UPCOMING EVENT")
        XCTAssertEqual(presentation.dateText, "TODAY")
        XCTAssertEqual(
            presentation.metadata,
            "Starts in 10 minutes · Work Calendar"
        )
        XCTAssertFalse(presentation.timeText.isEmpty)
    }

    func testMissingLocationAndCalendarAreOmittedFromMetadata() {
        let presentation = makePresentation(
            startOffset: 60,
            calendarTitle: nil,
            location: "   "
        )

        XCTAssertEqual(presentation.metadata, "Starts in 1 minute")
    }

    func testLocationIsUsedOnlyWhenCalendarNameIsUnavailable() {
        let presentation = makePresentation(
            startOffset: 10 * 60,
            calendarTitle: nil,
            location: "Room 4"
        )

        XCTAssertEqual(presentation.metadata, "Starts in 10 minutes · Room 4")
    }

    func testAllDayEventUsesStableAllDayTimeLabel() {
        let presentation = makePresentation(
            startOffset: 0,
            calendarTitle: "Personal",
            isAllDay: true
        )

        XCTAssertEqual(presentation.timeText, "ALL DAY")
        XCTAssertEqual(presentation.dateText, "TODAY")
    }

    func testRelativeStartCoversNowPastAndHourScaleWithoutTicking() {
        func relativeText(_ offset: TimeInterval) -> String? {
            makePresentation(startOffset: offset, calendarTitle: nil).metadata
        }

        XCTAssertEqual(relativeText(0), "Starts now")
        XCTAssertEqual(relativeText(-60), "Started 1 minute ago")
        XCTAssertEqual(relativeText(-300), "Started 5 minutes ago")
        XCTAssertEqual(relativeText(3_600), "Starts in 1 hour")
        XCTAssertEqual(relativeText(7_200), "Starts in 2 hours")
    }

    func testTomorrowAndLaterDatesUseContextualDateLabels() {
        XCTAssertEqual(makePresentation(startOffset: 26 * 3_600).dateText, "TOMORROW")
        XCTAssertEqual(makePresentation(startOffset: -26 * 3_600).dateText, "YESTERDAY")

        let later = makePresentation(startOffset: 3 * 24 * 3_600).dateText
        XCTAssertNotEqual(later, "TODAY")
        XCTAssertNotEqual(later, "TOMORROW")
        XCTAssertEqual(later, later.uppercased())
        XCTAssertTrue(later.contains("JAN") || later.contains("1"), "Unexpected label: \(later)")
    }

    func testReminderWithoutEventContextFallsBackToTriggerDateAndDetail() {
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .local,
                sourceIdentifier: "local",
                occurrenceDate: now,
                revision: nil
            ),
            title: "Stretch",
            detail: "Local reminder",
            triggerDate: now,
            expirationDate: nil,
            presentationMode: .overlay
        )
        let presentation = ReminderStripPresentation(
            reminder: reminder,
            now: now,
            calendar: calendar,
            locale: locale
        )

        XCTAssertEqual(presentation.eyebrow, "REMINDER")
        XCTAssertEqual(presentation.dateText, "TODAY")
        XCTAssertEqual(presentation.metadata, "Local reminder")
        XCTAssertEqual(presentation.accentHex, ReminderStripPresentation.fallbackAccentHex)
        XCTAssertFalse(presentation.hasSource)
    }

    func testAccentUsesCalendarColourAndFallsBackWhenAbsentOrMalformed() {
        XCTAssertEqual(makePresentation(startOffset: 0, colorHex: "#B05A2C").accentHex, "#B05A2C")
        XCTAssertEqual(
            makePresentation(startOffset: 0, colorHex: nil).accentHex,
            ReminderStripPresentation.fallbackAccentHex
        )
        XCTAssertNotNil(ReminderStripStyle.color(fromHex: "#B05A2C"))
        XCTAssertNotNil(ReminderStripStyle.color(fromHex: "B05A2CFF"))
        XCTAssertNil(ReminderStripStyle.color(fromHex: "not-a-colour"))
        XCTAssertNil(ReminderStripStyle.color(fromHex: "#12345"))
    }

    func testAccessibilityLabelCarriesTimeTitleAndMetadata() {
        let presentation = makePresentation(
            startOffset: 10 * 60,
            calendarTitle: "Work Calendar",
            location: nil
        )

        let label = presentation.accessibilityLabel
        XCTAssertTrue(label.contains(presentation.title))
        XCTAssertTrue(label.contains(presentation.timeText))
        XCTAssertTrue(label.contains("Work Calendar"))
    }

    func testCalendarReminderMapperCarriesEventContextIntoTheReminder() {
        let start = Date(timeIntervalSince1970: 1_800_003_600)
        let snapshot = CalendarEventSnapshot(
            eventIdentifier: "event",
            recurringEventIdentifier: nil,
            stableOccurrenceValue: "time:1800003600",
            stableOccurrenceDate: start,
            calendarIdentifier: "calendar",
            calendarTitle: "Work Calendar",
            calendarColorHex: "#3F7DE0",
            title: "Design review",
            location: "  Room 4 ",
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            reminders: [.init(method: "popup", minutes: 10, duplicateOrdinal: 0)],
            sourceURL: nil
        )

        let reminders = CalendarReminderMapper().reminders(from: snapshot)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.eventContext?.startDate, start)
        XCTAssertEqual(reminders.first?.eventContext?.calendarTitle, "Work Calendar")
        XCTAssertEqual(reminders.first?.eventContext?.location, "Room 4")
        XCTAssertEqual(reminders.first?.eventContext?.calendarColorHex, "#3F7DE0")
        XCTAssertEqual(reminders.first?.eventContext?.isAllDay, false)
        XCTAssertEqual(reminders.first?.triggerDate, start.addingTimeInterval(-600))
    }

    @MainActor
    func testAccessibilityTextIncreasesIntrinsicHeightWithoutAHeightConstraint() {
        let presentation = makePresentation(
            startOffset: 10 * 60,
            calendarTitle: "Engineering Leadership Calendar",
            location: nil
        )
        let view = ReminderControlStripView(
            presentation: presentation,
            isPerformingAction: false,
            actionErrorMessage: nil,
            onOpen: {},
            onSnooze: {},
            onDismiss: {}
        )
        let ordinary = NSHostingView(rootView: view)
        let accessible = NSHostingView(
            rootView: view.environment(\.dynamicTypeSize, .accessibility3)
        )

        ordinary.layoutSubtreeIfNeeded()
        accessible.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(accessible.fittingSize.height, ordinary.fittingSize.height)
    }

    @MainActor
    func testStoreKeepsActionErrorVisibleAfterActionEnds() {
        let store = ReminderOverlayStore()
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .local,
                sourceIdentifier: "error",
                occurrenceDate: now,
                revision: nil
            ),
            title: "Stretch",
            detail: nil,
            triggerDate: now,
            expirationDate: nil,
            presentationMode: .overlay
        )

        store.present(reminder, now: now)
        store.beginAction()
        store.endAction(errorMessage: "This reminder could not be snoozed.")

        XCTAssertFalse(store.isPerformingAction)
        XCTAssertEqual(store.actionErrorMessage, "This reminder could not be snoozed.")
        XCTAssertNotNil(store.reminder)
    }

    @MainActor
    func testStoreResetsTimedExitAnimationForEachPresentation() {
        let store = ReminderOverlayStore()
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .local,
                sourceIdentifier: "animation-state",
                occurrenceDate: now,
                revision: nil
            ),
            title: "Stretch",
            detail: nil,
            triggerDate: now,
            expirationDate: nil,
            presentationMode: .overlay
        )

        store.present(reminder, now: now)
        XCTAssertFalse(store.isAnimatingOut)

        store.beginExitAnimation()
        XCTAssertTrue(store.isAnimatingOut)

        store.present(reminder, now: now)
        XCTAssertFalse(store.isAnimatingOut)

        store.beginExitAnimation()
        store.clear()
        XCTAssertFalse(store.isAnimatingOut)
    }

    private func makePresentation(
        startOffset: TimeInterval,
        calendarTitle: String? = "Work Calendar",
        location: String? = nil,
        colorHex: String? = "#3F7DE0",
        isAllDay: Bool? = nil
    ) -> ReminderStripPresentation {
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: "event",
                occurrenceDate: now,
                revision: nil
            ),
            title: "Design review",
            detail: "unused",
            triggerDate: now,
            expirationDate: nil,
            presentationMode: .overlay,
            eventContext: ReminderEventContext(
                startDate: now.addingTimeInterval(startOffset),
                calendarTitle: calendarTitle,
                location: location,
                calendarColorHex: colorHex,
                isAllDay: isAllDay
            )
        )
        return ReminderStripPresentation(
            reminder: reminder,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }
}
