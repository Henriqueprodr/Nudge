import Foundation

/// Stores nag pacing history as a small JSON file in Application Support.
///
/// A file keeps this purely local, regenerable data out of the SwiftData schema, so adding it
/// needs no migration of the cached tasks and calendar events. A missing or unreadable file
/// simply starts the history over.
@MainActor
final class FileTaskNagHistoryRepository: TaskNagHistoryRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = FileTaskNagHistoryRepository.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Nudge", isDirectory: true)
            .appendingPathComponent("TaskNagHistory.json")
    }

    func fetchHistory() -> TaskNagHistory {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? decoder.decode(TaskNagHistory.self, from: data) else {
            return .empty
        }
        return history
    }

    func save(_ history: TaskNagHistory) {
        guard let data = try? encoder.encode(history) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
