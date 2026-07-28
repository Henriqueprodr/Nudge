@MainActor
protocol TaskRepository {
    func fetchIncompleteTasks() throws -> [TaskItem]
    func fetchTaskLists() throws -> [TaskList]
    func fetchTask(identifier: String) throws -> TaskItem?
    func saveTask(_ task: TaskItem) throws
    func replaceCache(taskLists: [TaskList], tasks: [TaskItem]) throws
}
