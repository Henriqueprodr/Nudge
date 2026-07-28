import Foundation
import SwiftData

@MainActor
final class LocalRepositoryContainer {
    enum RecoveryStatus: Equatable {
        case normal
        case recovered(URL)
        case inMemoryFallback

        var message: String? {
            switch self {
            case .normal:
                return nil
            case .recovered:
                return "An unreadable local cache was preserved for recovery and a fresh cache was created."
            case .inMemoryFallback:
                return "Persistent local storage is unavailable. Nudge is using a temporary in-memory cache."
            }
        }
    }

    struct OpenResult {
        let container: LocalRepositoryContainer
        let recoveryStatus: RecoveryStatus
    }

    let modelContainer: ModelContainer
    let taskRepository: SwiftDataTaskRepository
    let reminderDeliveryRepository: SwiftDataReminderDeliveryRepository
    let taskPanelStateRepository: SwiftDataTaskPanelStateRepository
    let syncMetadataRepository: SwiftDataSyncMetadataRepository
    let taskPendingActionRepository: SwiftDataTaskPendingActionRepository
    let calendarCacheRepository: SwiftDataCalendarCacheRepository

    init(isStoredInMemoryOnly: Bool = false, storeURL: URL? = nil) throws {
        let schema = Schema(versionedSchema: NudgeSchemaV4.self)
        let configuration: ModelConfiguration
        if let storeURL, !isStoredInMemoryOnly {
            configuration = ModelConfiguration(
                "NudgeLocalCache",
                schema: schema,
                url: storeURL
            )
        } else {
            configuration = ModelConfiguration(
                "NudgeLocalCache",
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }
        modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: NudgeSchemaMigrationPlan.self,
            configurations: [configuration]
        )

        let modelContext = ModelContext(modelContainer)
        taskRepository = SwiftDataTaskRepository(modelContext: modelContext)
        reminderDeliveryRepository = SwiftDataReminderDeliveryRepository(modelContext: modelContext)
        taskPanelStateRepository = SwiftDataTaskPanelStateRepository(modelContext: modelContext)
        syncMetadataRepository = SwiftDataSyncMetadataRepository(modelContext: modelContext)
        taskPendingActionRepository = SwiftDataTaskPendingActionRepository(modelContext: modelContext)
        calendarCacheRepository = SwiftDataCalendarCacheRepository(modelContext: modelContext)
    }

    static func openRecovering(
        storeURL: URL = defaultStoreURL,
        recoveryRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> OpenResult {
        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return OpenResult(
                container: try LocalRepositoryContainer(storeURL: storeURL),
                recoveryStatus: .normal
            )
        } catch {
            let storeFiles = [
                storeURL,
                URL(fileURLWithPath: storeURL.path + "-shm"),
                URL(fileURLWithPath: storeURL.path + "-wal"),
            ].filter { fileManager.fileExists(atPath: $0.path) }
            if !storeFiles.isEmpty {
                do {
                    let recoveryRoot = recoveryRootURL
                        ?? storeURL.deletingLastPathComponent()
                            .appendingPathComponent("Nudge Recovery", isDirectory: true)
                    let formatter = ISO8601DateFormatter()
                    let folderName = formatter.string(from: Date())
                        .replacingOccurrences(of: ":", with: "-")
                    let recoveryFolder = recoveryRoot.appendingPathComponent(
                        folderName,
                        isDirectory: true
                    )
                    try fileManager.createDirectory(
                        at: recoveryFolder,
                        withIntermediateDirectories: true
                    )
                    for file in storeFiles {
                        try fileManager.moveItem(
                            at: file,
                            to: recoveryFolder.appendingPathComponent(file.lastPathComponent)
                        )
                    }
                    return OpenResult(
                        container: try LocalRepositoryContainer(storeURL: storeURL),
                        recoveryStatus: .recovered(recoveryFolder)
                    )
                } catch {
                    // Preserve the original files and fall through to the in-memory cache.
                }
            }
            return OpenResult(
                container: try! LocalRepositoryContainer(isStoredInMemoryOnly: true),
                recoveryStatus: .inMemoryFallback
            )
        }
    }

    private static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NudgeLocalCache.store")
    }
}
