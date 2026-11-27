import Foundation

/// Routes provider-neutral `ReminderAction`s from the overlay to Google Tasks.
@MainActor
final class ReminderActionRouter {
    private let taskRepository: any TaskRepository
    private let taskActions: GoogleTasksActionCoordinator
    private let taskNags: TaskNagCoordinator

    init(
        taskRepository: any TaskRepository,
        taskActions: GoogleTasksActionCoordinator,
        taskNags: TaskNagCoordinator
    ) {
        self.taskRepository = taskRepository
        self.taskActions = taskActions
        self.taskNags = taskNags
    }

    func perform(_ action: ReminderAction, for reminder: Reminder) async -> Bool {
        switch action {
        case .completeTask:
            return await completePrimaryTask(of: reminder)
        case .notToday:
            taskNags.silenceUntilTomorrow(reminder)
            return true
        }
    }

    private func completePrimaryTask(of reminder: Reminder) async -> Bool {
        guard let taskID = reminder.taskContext?.primaryTaskID,
              let task = try? taskRepository.fetchTask(identifier: taskID),
              task.isIncomplete else {
            return false
        }
        await taskActions.complete(task)
        // The action coordinator rolls the cache back on failure, so the cache is the truth.
        let stored = try? taskRepository.fetchTask(identifier: taskID)
        let didComplete = stored == nil || stored?.completionState == .completed
        if didComplete {
            taskNags.recompute()
        }
        return didComplete
    }
}
