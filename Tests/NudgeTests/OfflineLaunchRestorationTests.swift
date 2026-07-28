import Foundation
import XCTest
@testable import Nudge

final class OfflineLaunchRestorationTests: XCTestCase {
    @MainActor
    func testFreshStoreRestoresCachedTasksAndVisibleCornerPanelWithoutNetwork() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let storeURL = temporaryDirectory.appendingPathComponent("NudgeLocalCache.store")
        let generalTask = TaskItem(
            id: "general-task",
            taskListID: "general",
            title: "General cached task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        let workflowTask = TaskItem(
            id: "workflow-task",
            taskListID: "workflow",
            title: "Workflow task visible while offline",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        do {
            let firstLaunchContainer = try LocalRepositoryContainer(storeURL: storeURL)
            try firstLaunchContainer.taskRepository.replaceCache(
                taskLists: [
                    TaskList(id: "general", title: "General"),
                    TaskList(id: "workflow", title: "AI Workflow Automation"),
                ],
                tasks: [generalTask, workflowTask]
            )
            try firstLaunchContainer.taskPanelStateRepository.save(
                TaskPanelState(
                    isEnabled: true,
                    displayMode: .expanded,
                    corner: .bottomTrailing,
                    selectedTaskListID: "workflow"
                )
            )
        }

        let relaunchedContainer = try LocalRepositoryContainer(storeURL: storeURL)
        let freshStore = TaskPanelStore(
            taskRepository: relaunchedContainer.taskRepository,
            stateRepository: relaunchedContainer.taskPanelStateRepository
        )
        let controller = TaskPanelWindowController(store: freshStore)
        defer {
            controller.hide()
        }

        controller.restoreIfEnabled()

        XCTAssertEqual(freshStore.displayedTasks, [workflowTask])
        XCTAssertEqual(freshStore.selectedTaskList?.title, "AI Workflow Automation")
        XCTAssertEqual(freshStore.state.corner, .bottomTrailing)
        XCTAssertTrue(freshStore.state.isEnabled)
        XCTAssertTrue(controller.isVisible)
    }

    @MainActor
    func testTaskPanelStoreFiltersOneCachedListAndSupportsAllLists() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let generalTask = TaskItem(
            id: "general-task",
            taskListID: "general",
            title: "General task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        let workflowTask = TaskItem(
            id: "workflow-task",
            taskListID: "workflow",
            title: "Workflow task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        try container.taskRepository.replaceCache(
            taskLists: [
                TaskList(id: "general", title: "General"),
                TaskList(id: "workflow", title: "AI Workflow Automation"),
                TaskList(id: "empty", title: "Empty List"),
            ],
            tasks: [generalTask, workflowTask]
        )
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )

        XCTAssertNil(store.state.selectedTaskListID)
        XCTAssertEqual(Set(store.displayedTasks.map(\.id)), ["general-task", "workflow-task"])

        store.selectTaskList("general")

        XCTAssertEqual(store.displayedTasks, [generalTask])
        XCTAssertEqual(store.selectedTaskList?.title, "General")
        XCTAssertEqual(
            try container.taskPanelStateRepository.fetchState()?.selectedTaskListID,
            "general"
        )

        store.selectTaskList("empty")

        XCTAssertTrue(store.displayedTasks.isEmpty)
        XCTAssertEqual(store.selectedTaskList?.title, "Empty List")

        store.selectTaskList(nil)

        XCTAssertEqual(Set(store.displayedTasks.map(\.id)), ["general-task", "workflow-task"])
    }

    @MainActor
    func testTaskPanelShowsEveryFilteredTaskDespiteLegacyPersistedLimit() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        var tasks = (0..<30).map { index in
            TaskItem(
                id: "general-\(index)",
                taskListID: "general",
                title: "General \(index)",
                notes: nil,
                completionState: .incomplete,
                dueDate: nil,
                localTimeOverride: nil
            )
        }
        tasks.append(
            TaskItem(
                id: "general-snoozed",
                taskListID: "general",
                title: "Snoozed",
                notes: nil,
                completionState: .incomplete,
                dueDate: nil,
                localTimeOverride: nil,
                locallySnoozedUntil: Date().addingTimeInterval(3_600)
            )
        )
        tasks.append(
            TaskItem(
                id: "other",
                taskListID: "other",
                title: "Other list",
                notes: nil,
                completionState: .incomplete,
                dueDate: nil,
                localTimeOverride: nil
            )
        )
        try container.taskRepository.replaceCache(
            taskLists: [
                TaskList(id: "general", title: "General"),
                TaskList(id: "other", title: "Other"),
            ],
            tasks: tasks
        )
        try container.taskPanelStateRepository.save(
            TaskPanelState(
                isEnabled: true,
                displayMode: .expanded,
                corner: .topTrailing,
                selectedTaskListID: "general",
                maximumVisibleTaskCount: 1
            )
        )

        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )

        XCTAssertEqual(store.state.maximumVisibleTaskCount, 1)
        XCTAssertEqual(store.filteredTasks.count, 30)
        XCTAssertEqual(store.displayedTasks.count, 30)
        XCTAssertFalse(store.displayedTasks.contains(where: { $0.id == "general-snoozed" }))
        XCTAssertFalse(store.displayedTasks.contains(where: { $0.id == "other" }))
    }

    @MainActor
    func testTaskPanelStoreFallsBackWhenSelectedListDisappears() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let generalTask = TaskItem(
            id: "general-task",
            taskListID: "general",
            title: "General task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        try container.taskRepository.replaceCache(
            taskLists: [
                TaskList(id: "general", title: "General"),
                TaskList(id: "workflow", title: "AI Workflow Automation"),
            ],
            tasks: [generalTask]
        )
        try container.taskPanelStateRepository.save(
            TaskPanelState(
                isEnabled: true,
                displayMode: .expanded,
                corner: .topTrailing,
                selectedTaskListID: "workflow"
            )
        )
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        XCTAssertEqual(store.state.selectedTaskListID, "workflow")
        XCTAssertTrue(store.displayedTasks.isEmpty)

        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "general", title: "General")],
            tasks: [generalTask]
        )
        store.restore()

        XCTAssertNil(store.state.selectedTaskListID)
        XCTAssertEqual(store.displayedTasks, [generalTask])
        XCTAssertNil(try container.taskPanelStateRepository.fetchState()?.selectedTaskListID)
    }

    @MainActor
    func testTaskPanelSortsByPriorityThenTitleAndIdentifier() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let tasks = [
            makePriorityTask(id: "none", title: "Alpha", priority: .none),
            makePriorityTask(id: "low", title: "Alpha", priority: .low),
            makePriorityTask(id: "medium", title: "Zulu", priority: .medium),
            makePriorityTask(id: "high-b", title: "Same", priority: .high),
            makePriorityTask(id: "high-a", title: "Same", priority: .high),
            makePriorityTask(id: "high-alpha", title: "Alpha", priority: .high),
        ]
        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list", title: "Inbox")],
            tasks: tasks
        )
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )

        XCTAssertEqual(
            store.displayedTasks.map(\.id),
            ["high-alpha", "high-a", "high-b", "medium", "low", "none"]
        )
    }

    private func makePriorityTask(
        id: String,
        title: String,
        priority: TaskPriority
    ) -> TaskItem {
        TaskItem(
            id: id,
            taskListID: "list",
            title: title,
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil,
            priority: priority
        )
    }
}
