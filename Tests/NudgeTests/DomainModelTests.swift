import Foundation
import XCTest
@testable import Nudge

final class DomainModelTests: XCTestCase {
    func testDateOnlyDueDateAndLocalTimeOverrideRoundTripWithoutConflation() throws {
        let task = TaskItem(
            id: "task-1",
            taskListID: "list-1",
            title: "Submit report",
            notes: nil,
            completionState: .incomplete,
            dueDate: TaskItem.DueDate(year: 2026, month: 7, day: 21),
            localTimeOverride: TaskItem.LocalTimeOverride(
                hour: 9,
                minute: 30,
                timeZoneIdentifier: "America/Sao_Paulo"
            )
        )

        let encoded = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: encoded)

        XCTAssertEqual(decoded, task)
        XCTAssertEqual(decoded.dueDate, TaskItem.DueDate(year: 2026, month: 7, day: 21))
        XCTAssertEqual(decoded.localTimeOverride?.hour, 9)
    }

    func testRecurringOccurrencesHaveDistinctIdentities() {
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)

        let first = ReminderOccurrenceID(
            sourceKind: .calendar,
            sourceIdentifier: "event-1",
            occurrenceDate: firstDate,
            revision: "1"
        )
        let second = ReminderOccurrenceID(
            sourceKind: .calendar,
            sourceIdentifier: "event-1",
            occurrenceDate: secondDate,
            revision: "1"
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 2)
    }

    func testLegacyTaskPanelStateDefaultsToAllLists() throws {
        let legacyState = Data(
            """
            {
              "isEnabled": true,
              "displayMode": "expanded",
              "corner": "Top Right"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(TaskPanelState.self, from: legacyState)

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.displayMode, .expanded)
        XCTAssertEqual(decoded.corner, .topTrailing)
        XCTAssertNil(decoded.selectedTaskListID)
        XCTAssertEqual(decoded.placementMode, .anchored)
        XCTAssertNil(decoded.normalizedPosition)
        XCTAssertEqual(decoded.expandedHeight, TaskPanelState.defaultExpandedHeight)
        XCTAssertEqual(decoded.priorityPalette, .defaultValue)
    }

    func testLegacyTaskItemDefaultsToNoPriority() throws {
        let legacyTask = Data(
            """
            {
              "id": "legacy",
              "taskListID": "list",
              "title": "Legacy task",
              "completionState": "incomplete"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(TaskItem.self, from: legacyTask)

        XCTAssertEqual(decoded.priority, .none)
    }

    func testPriorityPaletteValidatesAndRoundTrips() throws {
        let palette = TaskPriorityPalette(
            highColorHex: "aa0000",
            mediumColorHex: "#bb7700",
            lowColorHex: "not-a-color"
        )

        XCTAssertEqual(palette.highColorHex, "#AA0000")
        XCTAssertEqual(palette.mediumColorHex, "#BB7700")
        XCTAssertEqual(palette.lowColorHex, TaskPriorityPalette.defaultValue.lowColorHex)
        XCTAssertEqual(
            try JSONDecoder().decode(
                TaskPriorityPalette.self,
                from: JSONEncoder().encode(palette)
            ),
            palette
        )
    }
}
