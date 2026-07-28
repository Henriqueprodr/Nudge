import Foundation
import SwiftData

@Model
final class StoredSyncMetadata {
    var statusRawValue: String
    var lastAttemptAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var statusMessage: String?

    init(metadata: SyncMetadata) {
        statusRawValue = metadata.status.rawValue
        lastAttemptAt = metadata.lastAttemptAt
        lastSuccessfulRefreshAt = metadata.lastSuccessfulRefreshAt
        statusMessage = metadata.statusMessage
    }

    func update(from metadata: SyncMetadata) {
        statusRawValue = metadata.status.rawValue
        lastAttemptAt = metadata.lastAttemptAt
        lastSuccessfulRefreshAt = metadata.lastSuccessfulRefreshAt
        statusMessage = metadata.statusMessage
    }

    func domainValue() -> SyncMetadata? {
        guard let status = SyncMetadata.Status(rawValue: statusRawValue) else {
            return nil
        }

        return SyncMetadata(
            status: status,
            lastAttemptAt: lastAttemptAt,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            statusMessage: statusMessage
        )
    }
}
