@MainActor
protocol TaskPendingActionRepository {
    func fetchActions() throws -> [TaskPendingAction]
    func save(_ action: TaskPendingAction) throws
    func delete(_ action: TaskPendingAction) throws
}
