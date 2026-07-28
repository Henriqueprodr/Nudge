@MainActor
protocol TaskPanelStateRepository {
    func fetchState() throws -> TaskPanelState?
    func save(_ state: TaskPanelState) throws
}
