@MainActor
protocol TaskNagHistoryRepository {
    func fetchHistory() -> TaskNagHistory
    func save(_ history: TaskNagHistory)
}
