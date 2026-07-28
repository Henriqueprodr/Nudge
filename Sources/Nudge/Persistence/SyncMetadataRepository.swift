@MainActor
protocol SyncMetadataRepository {
    func fetchMetadata() throws -> SyncMetadata?
    func save(_ metadata: SyncMetadata) throws
}
