import Foundation
import SwiftData

@Model
final class StoredTaskPendingAction {
    @Attribute(.unique) var identifier: UUID
    var kindRawValue: String
    var taskIdentifier: String
    var taskListIdentifier: String
    var originalTaskData: Data
    var stateRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var failureMessage: String?

    init(action: TaskPendingAction) throws {
        identifier = action.id
        kindRawValue = action.kind.rawValue
        taskIdentifier = action.taskID
        taskListIdentifier = action.taskListID
        originalTaskData = try JSONEncoder().encode(action.originalTask)
        stateRawValue = action.state.rawValue
        createdAt = action.createdAt
        updatedAt = action.updatedAt
        failureMessage = action.failureMessage
    }

    func update(from action: TaskPendingAction) throws {
        kindRawValue = action.kind.rawValue
        taskIdentifier = action.taskID
        taskListIdentifier = action.taskListID
        originalTaskData = try JSONEncoder().encode(action.originalTask)
        stateRawValue = action.state.rawValue
        createdAt = action.createdAt
        updatedAt = action.updatedAt
        failureMessage = action.failureMessage
    }

    func domainValue() -> TaskPendingAction? {
        guard
            let kind = TaskPendingAction.Kind(rawValue: kindRawValue),
            let state = TaskPendingAction.State(rawValue: stateRawValue),
            let originalTask = try? JSONDecoder().decode(TaskItem.self, from: originalTaskData)
        else {
            return nil
        }
        return TaskPendingAction(
            id: identifier,
            kind: kind,
            taskID: taskIdentifier,
            taskListID: taskListIdentifier,
            originalTask: originalTask,
            state: state,
            createdAt: createdAt,
            updatedAt: updatedAt,
            failureMessage: failureMessage
        )
    }
}
