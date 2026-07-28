import Foundation

struct TaskPendingAction: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case complete
    }

    enum State: String, Codable, Sendable {
        case pending
        case failed
    }

    let id: UUID
    let kind: Kind
    let taskID: String
    let taskListID: String
    let originalTask: TaskItem
    var state: State
    var createdAt: Date
    var updatedAt: Date
    var failureMessage: String?
}
