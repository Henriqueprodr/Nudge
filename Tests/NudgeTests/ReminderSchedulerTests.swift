import Foundation
import XCTest
@testable import Nudge

final class ReminderSchedulerTests: XCTestCase {
    @MainActor
    func testRepeatedSchedulingPresentsOccurrenceOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let scheduler = ReminderScheduler(
            repository: container.reminderDeliveryRepository,
            clock: clock
        )
        let reminder = makeReminder(identifier: "deduplicated", triggerDate: now)

        XCTAssertEqual(try scheduler.rebuildSchedule(from: [reminder]), [.present(reminder)])
        try scheduler.markPresented(reminder.occurrenceID)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.present(reminder)],
            "An unacted confirmed presentation remains recoverable after relaunch."
        )
        try scheduler.markActed(reminder.occurrenceID)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.ignored(reminder.occurrenceID)]
        )
    }

    @MainActor
    func testSnoozedReminderReturnsOnceAtSnoozeDate() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let scheduler = ReminderScheduler(
            repository: container.reminderDeliveryRepository,
            clock: clock
        )
        let reminder = makeReminder(identifier: "snoozed", triggerDate: now)
        let snoozeDate = now.addingTimeInterval(10 * 60)

        _ = try scheduler.rebuildSchedule(from: [reminder])
        try scheduler.snooze(reminder.occurrenceID, until: snoozeDate)

        clock.now = now.addingTimeInterval(5 * 60)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.scheduled(reminder.occurrenceID, snoozeDate)]
        )

        clock.now = snoozeDate
        XCTAssertEqual(try scheduler.rebuildSchedule(from: [reminder]), [.present(reminder)])
        try scheduler.markPresented(reminder.occurrenceID)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.present(reminder)]
        )
        try scheduler.dismiss(reminder.occurrenceID)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.ignored(reminder.occurrenceID)]
        )
    }

    @MainActor
    func testMissedWindowExpiresInsteadOfReplayingOldReminder() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let scheduler = ReminderScheduler(
            repository: container.reminderDeliveryRepository,
            clock: clock,
            policy: .init(missedWindowGraceInterval: 15 * 60)
        )
        let reminder = makeReminder(
            identifier: "expired",
            triggerDate: now.addingTimeInterval(-16 * 60)
        )

        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.expired(reminder.occurrenceID)]
        )
        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(for: reminder.occurrenceID)?.state,
            .expired
        )
    }

    @MainActor
    func testFutureReminderIsScheduledAndDismissedReminderStaysSuppressed() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let scheduler = ReminderScheduler(
            repository: container.reminderDeliveryRepository,
            clock: clock
        )
        let futureDate = now.addingTimeInterval(60)
        let reminder = makeReminder(identifier: "future", triggerDate: futureDate)

        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.scheduled(reminder.occurrenceID, futureDate)]
        )

        clock.now = futureDate
        XCTAssertEqual(try scheduler.rebuildSchedule(from: [reminder]), [.present(reminder)])
        try scheduler.dismiss(reminder.occurrenceID)
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.ignored(reminder.occurrenceID)]
        )
    }

    @MainActor
    func testLatePresentationConfirmationCannotOverwriteTerminalAction() throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let scheduler = ReminderScheduler(
            repository: container.reminderDeliveryRepository,
            clock: clock
        )
        let reminder = makeReminder(identifier: "late-confirmation", triggerDate: now)

        XCTAssertEqual(try scheduler.rebuildSchedule(from: [reminder]), [.present(reminder)])
        try scheduler.markActed(reminder.occurrenceID)
        try scheduler.markPresented(reminder.occurrenceID)

        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(
                for: reminder.occurrenceID
            )?.state,
            .acted
        )
        XCTAssertEqual(
            try scheduler.rebuildSchedule(from: [reminder]),
            [.ignored(reminder.occurrenceID)]
        )
    }

    private func makeReminder(identifier: String, triggerDate: Date) -> Reminder {
        Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: identifier,
                occurrenceDate: triggerDate,
                revision: nil
            ),
            title: "Test reminder",
            detail: nil,
            triggerDate: triggerDate,
            expirationDate: nil,
            presentationMode: .overlay
        )
    }
}
