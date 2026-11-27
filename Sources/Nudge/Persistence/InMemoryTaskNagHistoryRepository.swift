/// Volatile nag history for screenshot captures and hosted tests, which must not touch the
/// user's Application Support folder.
@MainActor
final class InMemoryTaskNagHistoryRepository: TaskNagHistoryRepository {
    private var history = TaskNagHistory.empty

    func fetchHistory() -> TaskNagHistory {
        history
    }

    func save(_ history: TaskNagHistory) {
        self.history = history
    }
}
