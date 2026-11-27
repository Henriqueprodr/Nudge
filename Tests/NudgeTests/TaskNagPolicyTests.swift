import Foundation
import XCTest
@testable import Nudge

final class TaskNagPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Friday 20 November 2026, at the given UTC hour.
    private func date(day: Int = 20, hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
        )!
    }

    private func task(
        _ id: String,
        dueDay: Int? = nil,
        priority: TaskPriority = .none
    ) -> TaskItem {
        TaskItem(
            id: id,
            taskListID: "list",
            title: "Task \(id)",
            notes: nil,
            completionState: .incomplete,
            dueDate: dueDay.map { TaskItem.DueDate(year: 2026, month: 11, day: $0) },
            localTimeOverride: nil,
            priority: priority
        )
    }

    private func history(
        firstSeen: Date,
        ids: [String],
        lastNagged: [String: Date] = [:],
        deliveries: [Date] = []
    ) -> TaskNagHistory {
        var history = TaskNagHistory()
        for id in ids {
            history.observations[id] = TaskNagObservation(
                firstSeenAt: firstSeen,
                lastNaggedAt: lastNagged[id],
                nagCount: lastNagged[id] == nil ? 0 : 1
            )
        }
        history.deliveredNagDates = deliveries
        return history
    }

    private var policy: TaskNagPolicy {
        TaskNagPolicy(settings: .defaultValue, calendar: calendar)
    }

    // MARK: Classification

    func testFutureTasksAreIgnoredAndOverdueTasksNagImmediately() {
        let now = date(hour: 12, minute: 7)
        let tasks = [task("future", dueDay: 25), task("late", dueDay: 17)]
        let reminder = policy.nextReminder(
            tasks: tasks,
            history: history(firstSeen: date(day: 10, hour: 9), ids: ["future", "late"]),
            now: now
        )

        XCTAssertEqual(reminder?.taskContext?.taskIDs, ["late"])
        XCTAssertEqual(reminder?.taskContext?.urgency, .overdue)
        XCTAssertEqual(reminder?.taskContext?.daysOverdue, 3)
        // Past slots are floored to a ten-minute bucket so recomputes share an identity.
        XCTAssertEqual(reminder?.triggerDate, date(hour: 12, minute: 0))
        XCTAssertEqual(reminder?.occurrenceID.sourceKind, .task)
        XCTAssertEqual(reminder?.actions, [.completeTask, .notToday])
    }

    func testRecomputingWithinTheSameBucketKeepsTheSameIdentity() {
        let tasks = [task("late", dueDay: 17)]
        let state = history(firstSeen: date(day: 10, hour: 9), ids: ["late"])
        let first = policy.nextReminder(tasks: tasks, history: state, now: date(hour: 12, minute: 1))
        let second = policy.nextReminder(tasks: tasks, history: state, now: date(hour: 12, minute: 9))
        XCTAssertEqual(first?.occurrenceID, second?.occurrenceID)
    }

    func testDueTodayWaitsForTheElevenOClockSlot() {
        let reminder = policy.nextReminder(
            tasks: [task("today", dueDay: 20)],
            history: history(firstSeen: date(day: 19, hour: 9), ids: ["today"]),
            now: date(hour: 9, minute: 30)
        )
        XCTAssertEqual(reminder?.triggerDate, date(hour: 11))
        XCTAssertEqual(reminder?.taskContext?.urgency, .dueToday)
    }

    func testDueTodayAfterBothSlotsIsNotNaggedAgainToday() {
        let reminder = policy.nextReminder(
            tasks: [task("today", dueDay: 20)],
            history: history(
                firstSeen: date(day: 19, hour: 9),
                ids: ["today"],
                lastNagged: ["today": date(hour: 16, minute: 2)]
            ),
            now: date(hour: 17)
        )
        XCTAssertNil(reminder)
    }

    // MARK: Cadence

    func testCadenceEscalatesWithTimeOverdue() {
        let lastNag = date(hour: 10)
        let now = date(hour: 10, minute: 30)
        func nextDate(dueDay: Int, priority: TaskPriority = .none) -> Date? {
            policy.nextReminder(
                tasks: [task("t", dueDay: dueDay, priority: priority)],
                history: history(
                    firstSeen: date(day: 1, hour: 9),
                    ids: ["t"],
                    lastNagged: ["t": lastNag]
                ),
                now: now
            )?.triggerDate
        }

        XCTAssertEqual(nextDate(dueDay: 19), date(hour: 14))
        XCTAssertEqual(nextDate(dueDay: 16), date(hour: 12))
        XCTAssertEqual(nextDate(dueDay: 10), date(hour: 11, minute: 30))
        // High priority moves one step faster.
        XCTAssertEqual(nextDate(dueDay: 19, priority: .high), date(hour: 12))
        XCTAssertEqual(nextDate(dueDay: 10, priority: .high), date(hour: 11))
    }

    func testUndatedTasksNagOnlyAfterTheyHaveLingered() {
        let now = date(hour: 12, minute: 3)
        let fresh = policy.nextReminder(
            tasks: [task("undated")],
            history: history(firstSeen: date(day: 19, hour: 9), ids: ["undated"]),
            now: now
        )
        XCTAssertNil(fresh)

        let lingering = policy.nextReminder(
            tasks: [task("undated")],
            history: history(firstSeen: date(day: 11, hour: 9), ids: ["undated"]),
            now: now
        )
        XCTAssertEqual(lingering?.taskContext?.urgency, .lingering)
        XCTAssertEqual(lingering?.taskContext?.daysOpen, 9)
        XCTAssertNil(lingering?.taskContext?.daysOverdue)

        var settings = TaskNagSettings.defaultValue
        settings.includesUndatedTasks = false
        let disabled = TaskNagPolicy(settings: settings, calendar: calendar).nextReminder(
            tasks: [task("undated")],
            history: history(firstSeen: date(day: 1, hour: 9), ids: ["undated"]),
            now: now
        )
        XCTAssertNil(disabled)
    }

    // MARK: Global pacing

    func testQuietHoursDeferToMorning() {
        let reminder = policy.nextReminder(
            tasks: [task("late", dueDay: 17)],
            history: history(firstSeen: date(day: 10, hour: 9), ids: ["late"]),
            now: date(hour: 23, minute: 15)
        )
        XCTAssertEqual(reminder?.triggerDate, date(day: 21, hour: 9))
    }

    func testDailyLimitDefersToTomorrow() {
        let deliveries = (0..<6).map { date(hour: 9 + $0) }
        let reminder = policy.nextReminder(
            tasks: [task("late", dueDay: 10)],
            history: history(
                firstSeen: date(day: 1, hour: 9),
                ids: ["late"],
                lastNagged: ["late": date(hour: 9)],
                deliveries: deliveries
            ),
            now: date(hour: 15, minute: 30)
        )
        XCTAssertEqual(reminder?.triggerDate, date(day: 21, hour: 9))
    }

    func testMinimumGapSpacesSeparateNags() {
        let reminder = policy.nextReminder(
            tasks: [task("late", dueDay: 17)],
            history: history(
                firstSeen: date(day: 10, hour: 9),
                ids: ["late"],
                deliveries: [date(hour: 12)]
            ),
            now: date(hour: 12, minute: 10)
        )
        XCTAssertEqual(reminder?.triggerDate, date(hour: 12, minute: 45))
    }

    func testSimultaneousTasksAreBatchedMostUrgentFirst() {
        let reminder = policy.nextReminder(
            tasks: [
                task("recent", dueDay: 19),
                task("ancient", dueDay: 5),
                task("undated"),
            ],
            history: history(firstSeen: date(day: 1, hour: 9), ids: ["recent", "ancient", "undated"]),
            now: date(hour: 12, minute: 4)
        )
        XCTAssertEqual(reminder?.taskContext?.taskIDs, ["ancient", "recent", "undated"])
        XCTAssertEqual(reminder?.taskContext?.urgency, .ancient)
        XCTAssertEqual(reminder?.title, "Task ancient")
        XCTAssertEqual(reminder?.occurrenceID.sourceIdentifier, "task-nag:ancient")
    }

    func testSilencedAndSnoozedTasksAreRespected() {
        var state = history(firstSeen: date(day: 1, hour: 9), ids: ["late", "other"])
        state.silence(["late"], until: date(day: 21, hour: 9))
        state.snooze(["other"], until: date(hour: 13, minute: 20))
        let reminder = policy.nextReminder(
            tasks: [task("late", dueDay: 17), task("other", dueDay: 18)],
            history: state,
            now: date(hour: 12, minute: 20)
        )
        XCTAssertEqual(reminder?.taskContext?.taskIDs, ["other"])
        XCTAssertEqual(reminder?.triggerDate, date(hour: 13, minute: 20))
    }

    func testDisabledSettingsProduceNoNags() {
        var settings = TaskNagSettings.defaultValue
        settings.isEnabled = false
        let reminder = TaskNagPolicy(settings: settings, calendar: calendar).nextReminder(
            tasks: [task("late", dueDay: 1)],
            history: history(firstSeen: date(day: 1, hour: 9), ids: ["late"]),
            now: date(hour: 12)
        )
        XCTAssertNil(reminder)
    }

    // MARK: History

    func testHistoryReconcilesFirstSeenAndForgetsRemovedTasks() {
        var state = TaskNagHistory()
        state.reconcile(withIncompleteTaskIDs: ["a", "b"], now: date(hour: 9))
        state.reconcile(withIncompleteTaskIDs: ["b", "c"], now: date(hour: 10))
        XCTAssertNil(state.observations["a"])
        XCTAssertEqual(state.observations["b"]?.firstSeenAt, date(hour: 9))
        XCTAssertEqual(state.observations["c"]?.firstSeenAt, date(hour: 10))

        state.snooze(["b"], until: date(hour: 11))
        state.recordDelivery(of: ["b"], at: date(hour: 12))
        XCTAssertNil(state.observations["b"]?.snoozedUntil)
        XCTAssertEqual(state.observations["b"]?.nagCount, 1)
        XCTAssertEqual(state.lastDeliveredNagDate, date(hour: 12))
    }

    // MARK: Presentation copy

    func testOverdueTaskPresentationUsesTheDueDateTheUserPicked() {
        let reminder = policy.nextReminder(
            tasks: [task("late", dueDay: 17), task("also", dueDay: 18)],
            history: history(firstSeen: date(day: 10, hour: 9), ids: ["late", "also"]),
            now: date(hour: 12, minute: 7)
        )!
        let presentation = ReminderStripPresentation(
            reminder: reminder,
            now: date(hour: 12, minute: 7),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(presentation.eyebrow, "2 TASKS STILL NOT DONE")
        XCTAssertEqual(presentation.title, "Task late + 1 more")
        XCTAssertEqual(presentation.timeText, "3 DAYS")
        XCTAssertEqual(presentation.dateText, "LATE")
        XCTAssertEqual(presentation.metadata, "You said you'd do it Nov 17 · 3 days ago")
        XCTAssertEqual(presentation.snoozeTitle, "Snooze 1h")
        XCTAssertEqual(presentation.actions, [.completeTask, .notToday])
        XCTAssertEqual(presentation.tone, .task(.overdue))
    }
}
