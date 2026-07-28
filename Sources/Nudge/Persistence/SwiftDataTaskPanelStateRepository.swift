import SwiftData

@MainActor
final class SwiftDataTaskPanelStateRepository: TaskPanelStateRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchState() throws -> TaskPanelState? {
        try modelContext.fetch(FetchDescriptor<StoredTaskPanelState>())
            .first?
            .domainValue()
    }

    func save(_ state: TaskPanelState) throws {
        if let storedState = try modelContext.fetch(FetchDescriptor<StoredTaskPanelState>()).first {
            storedState.update(from: state)
        } else {
            modelContext.insert(StoredTaskPanelState(state: state))
        }
        try modelContext.save()
    }
}
