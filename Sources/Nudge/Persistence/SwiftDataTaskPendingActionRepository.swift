import SwiftData

@MainActor
final class SwiftDataTaskPendingActionRepository: TaskPendingActionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchActions() throws -> [TaskPendingAction] {
        try modelContext.fetch(FetchDescriptor<StoredTaskPendingAction>())
            .compactMap { $0.domainValue() }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ action: TaskPendingAction) throws {
        let records = try modelContext.fetch(FetchDescriptor<StoredTaskPendingAction>())
        if let storedAction = records.first(where: { $0.identifier == action.id }) {
            try storedAction.update(from: action)
        } else {
            modelContext.insert(try StoredTaskPendingAction(action: action))
        }
        try modelContext.save()
    }

    func delete(_ action: TaskPendingAction) throws {
        let records = try modelContext.fetch(FetchDescriptor<StoredTaskPendingAction>())
        if let storedAction = records.first(where: { $0.identifier == action.id }) {
            modelContext.delete(storedAction)
            try modelContext.save()
        }
    }
}
