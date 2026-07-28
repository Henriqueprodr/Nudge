import Foundation
import SwiftData
import XCTest
@testable import Nudge

final class SwiftDataRepositoryTests: XCTestCase {
    @MainActor
    func testTaskCacheRoundTripFiltersCompletedTasksAndPreservesDateSemantics() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let incompleteTask = TaskItem(
            id: "task-1",
            taskListID: "list-1",
            title: "Cached incomplete task",
            notes: "Available offline",
            completionState: .incomplete,
            dueDate: TaskItem.DueDate(year: 2026, month: 7, day: 21),
            localTimeOverride: TaskItem.LocalTimeOverride(
                hour: 8,
                minute: 45,
                timeZoneIdentifier: "America/Sao_Paulo"
            )
        )
        let completedTask = TaskItem(
            id: "task-2",
            taskListID: "list-1",
            title: "Completed task",
            notes: nil,
            completionState: .completed,
            dueDate: nil,
            localTimeOverride: nil
        )

        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list-1", title: "Inbox")],
            tasks: [incompleteTask, completedTask]
        )

        XCTAssertEqual(try container.taskRepository.fetchTaskLists(), [TaskList(id: "list-1", title: "Inbox")])
        XCTAssertEqual(try container.taskRepository.fetchIncompleteTasks(), [incompleteTask])

        var refreshedTask = incompleteTask
        refreshedTask.title = "Refreshed title"
        refreshedTask.localTimeOverride = nil
        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list-1", title: "Inbox")],
            tasks: [refreshedTask]
        )

        var expectedReconciledTask = refreshedTask
        expectedReconciledTask.localTimeOverride = incompleteTask.localTimeOverride
        XCTAssertEqual(
            try container.taskRepository.fetchIncompleteTasks(),
            [expectedReconciledTask]
        )
    }

    @MainActor
    func testPanelDeliveryAndSyncMetadataRoundTrip() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let panelState = TaskPanelState(
            isEnabled: true,
            displayMode: .compact,
            corner: .bottomLeading,
            selectedTaskListID: "list-1"
        )
        let occurrenceID = ReminderOccurrenceID(
            sourceKind: .local,
            sourceIdentifier: "local-1",
            occurrenceDate: Date(timeIntervalSince1970: 50_000),
            revision: nil
        )
        let delivery = ReminderDeliveryRecord(
            occurrenceID: occurrenceID,
            state: .snoozed,
            scheduledAt: Date(timeIntervalSince1970: 49_000),
            presentedAt: Date(timeIntervalSince1970: 50_000),
            snoozedUntil: Date(timeIntervalSince1970: 51_000),
            updatedAt: Date(timeIntervalSince1970: 50_100)
        )
        let metadata = SyncMetadata(
            status: .stale,
            lastAttemptAt: Date(timeIntervalSince1970: 60_000),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 59_000),
            statusMessage: "Offline"
        )

        try container.taskPanelStateRepository.save(panelState)
        try container.reminderDeliveryRepository.save(delivery)
        try container.syncMetadataRepository.save(metadata)

        XCTAssertEqual(try container.taskPanelStateRepository.fetchState(), panelState)
        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(for: occurrenceID),
            delivery
        )
        XCTAssertEqual(try container.syncMetadataRepository.fetchMetadata(), metadata)
    }

    @MainActor
    func testCalendarListsEventsAndMetadataPersistInIndependentCaches() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let repository = container.calendarCacheRepository
        let calendar = CalendarDescriptor(
            id: "calendar",
            title: "Calendar",
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: true,
            defaultReminders: [.init(method: "popup", minutes: 10)]
        )
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let event = CalendarEventSnapshot(
            eventIdentifier: "event",
            recurringEventIdentifier: nil,
            stableOccurrenceValue: "time:2000000000",
            stableOccurrenceDate: start,
            calendarIdentifier: calendar.id,
            calendarTitle: calendar.title,
            calendarColorHex: calendar.backgroundColorHex,
            title: "Event",
            location: nil,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            reminders: [.init(method: "popup", minutes: 10, duplicateOrdinal: 0)],
            sourceURL: nil
        )
        let metadata = SyncMetadata(
            status: .current,
            lastAttemptAt: start,
            lastSuccessfulRefreshAt: start,
            statusMessage: nil
        )

        try repository.replaceCalendars([calendar])
        try repository.replaceEvents([event])
        try repository.saveMetadata(metadata)
        try repository.replaceCalendars([])

        XCTAssertEqual(try repository.fetchCalendars(), [])
        XCTAssertEqual(try repository.fetchEvents(), [event])
        XCTAssertEqual(try repository.fetchMetadata(), metadata)
    }
}
