import Foundation

struct GoogleTasksSnapshot: Equatable, Sendable {
    let taskLists: [TaskList]
    let tasks: [TaskItem]
}
