import SwiftData

@MainActor
final class SwiftDataSyncMetadataRepository: SyncMetadataRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchMetadata() throws -> SyncMetadata? {
        try modelContext.fetch(FetchDescriptor<StoredSyncMetadata>())
            .first?
            .domainValue()
    }

    func save(_ metadata: SyncMetadata) throws {
        if let storedMetadata = try modelContext.fetch(FetchDescriptor<StoredSyncMetadata>()).first {
            storedMetadata.update(from: metadata)
        } else {
            modelContext.insert(StoredSyncMetadata(metadata: metadata))
        }
        try modelContext.save()
    }
}
