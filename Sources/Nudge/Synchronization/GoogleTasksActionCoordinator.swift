import Foundation
import Observation

@MainActor
@Observable
final class GoogleTasksActionCoordinator {
    typealias NoticeSleeper = @MainActor (Duration) async throws -> Void

    private let authentication: any GoogleTasksAuthenticating
    private let provider: any GoogleTasksMutating
    private let taskRepository: any TaskRepository
    private let actionRepository: any TaskPendingActionRepository
    private let sourceOpener: any SystemBrowserOpening
    private let requestPostActionRefresh: @MainActor () -> Void
    private let cacheDidChange: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let noticeDuration: Duration
    private let noticeSleeper: NoticeSleeper
    private var noticeDismissalTask: Task<Void, Never>?

    private(set) var activeTaskIDs: Set<String> = []
    private(set) var errorMessage: String?

    init(
        authentication: any GoogleTasksAuthenticating,
        provider: any GoogleTasksMutating,
        taskRepository: any TaskRepository,
        actionRepository: any TaskPendingActionRepository,
        sourceOpener: any SystemBrowserOpening,
        requestPostActionRefresh: @escaping @MainActor () -> Void,
        cacheDidChange: @escaping @MainActor () -> Void,
        now: @escaping @MainActor () -> Date = Date.init,
        noticeDuration: Duration = .seconds(10),
        noticeSleeper: @escaping NoticeSleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.authentication = authentication
        self.provider = provider
        self.taskRepository = taskRepository
        self.actionRepository = actionRepository
        self.sourceOpener = sourceOpener
        self.requestPostActionRefresh = requestPostActionRefresh
        self.cacheDidChange = cacheDidChange
        self.now = now
        self.noticeDuration = noticeDuration
        self.noticeSleeper = noticeSleeper
    }

    func recoverPendingActions() {
        do {
            let actions = try actionRepository.fetchActions()
            for action in actions where action.state == .failed {
                try actionRepository.delete(action)
            }
            var recoveredCount = 0
            for action in actions where action.state == .pending {
                try taskRepository.saveTask(action.originalTask)
                try actionRepository.delete(action)
                recoveredCount += 1
            }
            if recoveredCount > 0 {
                presentNotice("An interrupted task completion was restored. You can try again.")
                cacheDidChange()
            }
        } catch {
            presentNotice("Pending task actions could not be recovered. Cached tasks were preserved.")
        }
    }

    func complete(_ task: TaskItem) async {
        guard activeTaskIDs.insert(task.id).inserted else {
            return
        }
        defer {
            activeTaskIDs.remove(task.id)
        }

        let actionDate = now()
        let action = TaskPendingAction(
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

        do {
            for previousAction in try actionRepository.fetchActions()
                where previousAction.taskID == task.id && previousAction.kind == .complete {
                try actionRepository.delete(previousAction)
            }
            try actionRepository.save(action)
            var completedTask = task
            completedTask.completionState = .completed
            try taskRepository.saveTask(completedTask)
            clearError()
            cacheDidChange()

            let accessToken = try await authentication.validAccessToken()
            try await provider.completeTask(
                taskListID: task.taskListID,
                taskID: task.id,
                accessToken: accessToken
            )
            try actionRepository.delete(action)
            requestPostActionRefresh()
        } catch {
            rollback(action, error: error)
        }
    }

    func open(_ task: TaskItem) {
        guard let url = task.webViewURL else {
            presentNotice("Google did not provide a supported link for this task.")
            return
        }
        if sourceOpener.open(url) {
            clearError()
        } else {
            presentNotice("The task could not be opened in Google Tasks.")
        }
    }

    func snooze(_ task: TaskItem, until date: Date) {
        modifyLocally(task) { updatedTask in
            updatedTask.locallySnoozedUntil = date
        }
    }

    func setTimeOverride(_ task: TaskItem, hour: Int?, minute: Int?) {
        modifyLocally(task) { updatedTask in
            if let hour, let minute {
                updatedTask.localTimeOverride = TaskItem.LocalTimeOverride(
                    hour: hour,
                    minute: minute,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            } else {
                updatedTask.localTimeOverride = nil
            }
        }
    }

    func setPriority(_ priority: TaskPriority, for task: TaskItem) {
        modifyLocally(task, requestsRefresh: false) { updatedTask in
            updatedTask.priority = priority
        }
    }

    func clearError() {
        noticeDismissalTask?.cancel()
        noticeDismissalTask = nil
        errorMessage = nil
    }

    private func modifyLocally(
        _ task: TaskItem,
        requestsRefresh: Bool = true,
        mutation: (inout TaskItem) -> Void
    ) {
        do {
            var updatedTask = task
            mutation(&updatedTask)
            try taskRepository.saveTask(updatedTask)
            clearError()
            cacheDidChange()
            if requestsRefresh {
                requestPostActionRefresh()
            }
        } catch {
            presentNotice("The local task change could not be saved. Cached tasks were preserved.")
        }
    }

    private func rollback(_ action: TaskPendingAction, error: Error) {
        let normalizedError = GoogleTasksError.normalized(error)
        do {
            try taskRepository.saveTask(action.originalTask)
            try actionRepository.delete(action)
            let failureMessage = normalizedError == .authenticationRequired
                ? "Task completion needs Google Tasks sign-in again. The cached task was restored."
                : "Task completion failed. The cached task was restored; try again."
            presentNotice(failureMessage)
        } catch {
            presentNotice("Task completion failed and its cached rollback needs attention.")
        }
        cacheDidChange()
    }

    private func presentNotice(_ message: String) {
        noticeDismissalTask?.cancel()
        errorMessage = message
        let duration = noticeDuration
        let sleeper = noticeSleeper
        noticeDismissalTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(duration)
            } catch {
                return
            }
            guard self?.errorMessage == message else {
                return
            }
            self?.errorMessage = nil
            self?.noticeDismissalTask = nil
        }
    }
}
