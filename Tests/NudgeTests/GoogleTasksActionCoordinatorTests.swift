import Foundation
import XCTest
@testable import Nudge

final class GoogleTasksActionCoordinatorTests: XCTestCase {
    @MainActor
    func testSuccessfulCompletionRunsOncePersistsOptimisticStateAndRequestsOneRefresh() async throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let task = makeTask(identifier: "complete-once")
        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list", title: "Inbox")],
            tasks: [task]
        )
        let mutator = ControlledTaskMutator()
        var refreshCount = 0
        var cacheChangeCount = 0
        let coordinator = makeCoordinator(
            container: container,
            mutator: mutator,
            requestRefresh: { refreshCount += 1 },
            cacheDidChange: { cacheChangeCount += 1 }
        )

        let first = Task { await coordinator.complete(task) }
        await waitUntil { mutator.callCount == 1 }
        let second = Task { await coordinator.complete(task) }
        await Task.yield()

        XCTAssertEqual(mutator.callCount, 1)
        XCTAssertTrue(try container.taskRepository.fetchIncompleteTasks().isEmpty)
        XCTAssertEqual(try container.taskPendingActionRepository.fetchActions().count, 1)

        mutator.succeed()
        await first.value
        await second.value

        XCTAssertEqual(mutator.callCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertGreaterThanOrEqual(cacheChangeCount, 1)
        XCTAssertTrue(try container.taskPendingActionRepository.fetchActions().isEmpty)
    }

    @MainActor
    func testFailedCompletionRollsBackCachedTaskAndClearsRecoveryJournal() async throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let task = makeTask(identifier: "rollback")
        try container.taskRepository.saveTask(task)
        let mutator = ControlledTaskMutator(error: GoogleTasksError.transportFailure)
        var refreshCount = 0
        let coordinator = makeCoordinator(
            container: container,
            mutator: mutator,
            requestRefresh: { refreshCount += 1 }
        )

        await coordinator.complete(task)

        XCTAssertEqual(
            try container.taskRepository.fetchTask(identifier: task.id)?.completionState,
            .incomplete
        )
        XCTAssertTrue(try container.taskPendingActionRepository.fetchActions().isEmpty)
        XCTAssertTrue(coordinator.errorMessage?.contains("restored") == true)
        XCTAssertEqual(refreshCount, 0)
    }

    @MainActor
    func testPendingCompletionRecoveryAfterRelaunchRestoresOriginalTask() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let storeURL = temporaryDirectory.appendingPathComponent("NudgeLocalCache.store")
        let task = makeTask(identifier: "recover")
        var optimisticallyCompletedTask = task
        optimisticallyCompletedTask.completionState = .completed
        let actionDate = Date(timeIntervalSince1970: 123)
        do {
            let firstLaunchContainer = try LocalRepositoryContainer(storeURL: storeURL)
            try firstLaunchContainer.taskRepository.saveTask(optimisticallyCompletedTask)
            try firstLaunchContainer.taskPendingActionRepository.save(
                TaskPendingAction(
                    id: UUID(),
                    kind: .complete,
                    taskID: task.id,
                    taskListID: task.taskListID,
                    originalTask: task,
                    state: .pending,
                    createdAt: actionDate,
                    updatedAt: actionDate,
                    failureMessage: nil
                )
            )
        }

        let relaunchedContainer = try LocalRepositoryContainer(storeURL: storeURL)
        var cacheChangeCount = 0
        let coordinator = makeCoordinator(
            container: relaunchedContainer,
            mutator: ControlledTaskMutator(),
            cacheDidChange: { cacheChangeCount += 1 }
        )

        coordinator.recoverPendingActions()

        XCTAssertEqual(
            try relaunchedContainer.taskRepository.fetchTask(identifier: task.id)?.completionState,
            .incomplete
        )
        XCTAssertTrue(try relaunchedContainer.taskPendingActionRepository.fetchActions().isEmpty)
        XCTAssertTrue(coordinator.errorMessage?.contains("restored") == true)
        XCTAssertEqual(cacheChangeCount, 1)
    }

    @MainActor
    func testHistoricalFailedActionIsPrunedWithoutResurfacingMessage() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let task = makeTask(identifier: "historical-failure")
        let date = Date(timeIntervalSince1970: 123)
        try container.taskPendingActionRepository.save(
            TaskPendingAction(
                id: UUID(),
                kind: .complete,
                taskID: task.id,
                taskListID: task.taskListID,
                originalTask: task,
                state: .failed,
                createdAt: date,
                updatedAt: date,
                failureMessage: "An interrupted completion was rolled back. Try again."
            )
        )
        let coordinator = makeCoordinator(
            container: container,
            mutator: ControlledTaskMutator()
        )

        coordinator.recoverPendingActions()

        XCTAssertTrue(try container.taskPendingActionRepository.fetchActions().isEmpty)
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    func testRecoveryNoticeCanBeDismissedAndExpiresAutomatically() async throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let coordinator = makeCoordinator(
            container: container,
            mutator: ControlledTaskMutator()
        )
        coordinator.open(makeTask(identifier: "missing-link"))
        XCTAssertNotNil(coordinator.errorMessage)

        coordinator.clearError()
        XCTAssertNil(coordinator.errorMessage)

        let expiringCoordinator = makeCoordinator(
            container: container,
            mutator: ControlledTaskMutator(),
            noticeDuration: .zero,
            noticeSleeper: { _ in }
        )
        expiringCoordinator.open(makeTask(identifier: "auto-expiring-link"))
        await Task.yield()
        await Task.yield()
        XCTAssertNil(expiringCoordinator.errorMessage)
    }

    @MainActor
    func testLocalSnoozeAndTimeOverridePersistAndRequestCoalescibleRefreshes() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let task = makeTask(identifier: "local-actions")
        try container.taskRepository.saveTask(task)
        var refreshCount = 0
        let now = Date(timeIntervalSince1970: 500)
        let coordinator = makeCoordinator(
            container: container,
            mutator: ControlledTaskMutator(),
            requestRefresh: { refreshCount += 1 },
            now: { now }
        )

        coordinator.snooze(task, until: now.addingTimeInterval(60 * 60))
        let snoozedTask = try XCTUnwrap(container.taskRepository.fetchTask(identifier: task.id))
        coordinator.setTimeOverride(snoozedTask, hour: 9, minute: 30)

        let updatedTask = try XCTUnwrap(container.taskRepository.fetchTask(identifier: task.id))
        XCTAssertEqual(updatedTask.locallySnoozedUntil, now.addingTimeInterval(60 * 60))
        XCTAssertEqual(updatedTask.localTimeOverride?.hour, 9)
        XCTAssertEqual(updatedTask.localTimeOverride?.minute, 30)
        XCTAssertEqual(refreshCount, 2)

        var remoteTask = task
        remoteTask.title = "Remote title"
        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list", title: "Inbox")],
            tasks: [remoteTask]
        )
        let reconciledTask = try XCTUnwrap(container.taskRepository.fetchTask(identifier: task.id))
        XCTAssertEqual(reconciledTask.locallySnoozedUntil, updatedTask.locallySnoozedUntil)
        XCTAssertEqual(reconciledTask.localTimeOverride, updatedTask.localTimeOverride)
    }

    @MainActor
    func testLocalPriorityPersistsAcrossRefreshWithoutRequestingGoogleRefresh() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let task = makeTask(identifier: "local-priority")
        try container.taskRepository.saveTask(task)
        var refreshCount = 0
        var cacheChangeCount = 0
        let coordinator = makeCoordinator(
            container: container,
            mutator: ControlledTaskMutator(),
            requestRefresh: { refreshCount += 1 },
            cacheDidChange: { cacheChangeCount += 1 }
        )

        coordinator.setPriority(.high, for: task)

        let prioritized = try XCTUnwrap(container.taskRepository.fetchTask(identifier: task.id))
        XCTAssertEqual(prioritized.priority, .high)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(cacheChangeCount, 1)

        var remoteTask = task
        remoteTask.title = "Remote title"
        try container.taskRepository.replaceCache(
            taskLists: [TaskList(id: "list", title: "Inbox")],
            tasks: [remoteTask]
        )

        let reconciled = try XCTUnwrap(container.taskRepository.fetchTask(identifier: task.id))
        XCTAssertEqual(reconciled.title, "Remote title")
        XCTAssertEqual(reconciled.priority, .high)
    }

    @MainActor
    func testOpenUsesProviderSuppliedWebViewLink() {
        let opener = RecordingBrowserOpener()
        let task = makeTask(identifier: "open", webViewURL: URL(string: "https://tasks.google.com/task/open")!)
        let coordinator = GoogleTasksActionCoordinator(
            authentication: ActionAuthentication(),
            provider: ControlledTaskMutator(),
            taskRepository: InMemoryTaskRepository(),
            actionRepository: InMemoryPendingActionRepository(),
            sourceOpener: opener,
            requestPostActionRefresh: {},
            cacheDidChange: {}
        )

        coordinator.open(task)

        XCTAssertEqual(opener.openedURLs, [URL(string: "https://tasks.google.com/task/open")!])
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    private func makeCoordinator(
        container: LocalRepositoryContainer,
        mutator: ControlledTaskMutator,
        requestRefresh: @escaping @MainActor () -> Void = {},
        cacheDidChange: @escaping @MainActor () -> Void = {},
        now: @escaping @MainActor () -> Date = Date.init,
        noticeDuration: Duration = .seconds(10),
        noticeSleeper: @escaping GoogleTasksActionCoordinator.NoticeSleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) -> GoogleTasksActionCoordinator {
        GoogleTasksActionCoordinator(
            authentication: ActionAuthentication(),
            provider: mutator,
            taskRepository: container.taskRepository,
            actionRepository: container.taskPendingActionRepository,
            sourceOpener: RecordingBrowserOpener(),
            requestPostActionRefresh: requestRefresh,
            cacheDidChange: cacheDidChange,
            now: now,
            noticeDuration: noticeDuration,
            noticeSleeper: noticeSleeper
        )
    }

    private func makeTask(identifier: String, webViewURL: URL? = nil) -> TaskItem {
        TaskItem(
            id: identifier,
            taskListID: "list",
            title: "Task",
            notes: nil,
            completionState: .incomplete,
            dueDate: TaskItem.DueDate(year: 2026, month: 7, day: 21),
            localTimeOverride: nil,
            webViewURL: webViewURL
        )
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 where !predicate() {
            await Task.yield()
        }
    }
}

@MainActor
private final class ControlledTaskMutator: GoogleTasksMutating {
    private let error: Error?
    private var continuation: CheckedContinuation<Void, Never>?
    private let blocksUntilReleased: Bool
    private(set) var callCount = 0

    init(error: Error? = nil, blocksUntilReleased: Bool? = nil) {
        self.error = error
        self.blocksUntilReleased = blocksUntilReleased ?? (error == nil)
    }

    func completeTask(
        taskListID: String,
        taskID: String,
        accessToken: String
    ) async throws {
        callCount += 1
        if let error {
            throw error
        }
        if blocksUntilReleased {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ActionAuthentication: GoogleTasksAuthenticating {
    var isClientIDConfigured = true
    var isConfigured = true
    func hasStoredClientSecret() throws -> Bool { true }
    func saveClientSecret(_ clientSecret: String) throws {}
    func deleteClientSecret() throws {}
    func hasStoredCredential() throws -> Bool { true }
    func signIn() async throws {}
    func signOut() throws {}
    func validAccessToken() async throws -> String { "access-token" }
}

@MainActor
private final class RecordingBrowserOpener: SystemBrowserOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

@MainActor
private final class InMemoryTaskRepository: TaskRepository {
    private var tasks: [String: TaskItem] = [:]
    func fetchIncompleteTasks() throws -> [TaskItem] { tasks.values.filter(\.isIncomplete) }
    func fetchTaskLists() throws -> [TaskList] { [] }
    func fetchTask(identifier: String) throws -> TaskItem? { tasks[identifier] }
    func saveTask(_ task: TaskItem) throws { tasks[task.id] = task }
    func replaceCache(taskLists: [TaskList], tasks: [TaskItem]) throws {
        self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }
}

@MainActor
private final class InMemoryPendingActionRepository: TaskPendingActionRepository {
    private var actions: [UUID: TaskPendingAction] = [:]
    func fetchActions() throws -> [TaskPendingAction] { Array(actions.values) }
    func save(_ action: TaskPendingAction) throws { actions[action.id] = action }
    func delete(_ action: TaskPendingAction) throws { actions[action.id] = nil }
}
