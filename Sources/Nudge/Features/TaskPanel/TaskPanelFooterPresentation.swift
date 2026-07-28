import Foundation

struct TaskPanelFooterPresentation: Equatable {
    let summary: String
    let detail: String

    init(summary: String, detail: String) {
        self.summary = summary
        self.detail = detail
    }

    init(
        taskCount: Int,
        metadata: SyncMetadata,
        now: Date = Date()
    ) {
        let taskCountDescription = "\(taskCount) \(taskCount == 1 ? "task" : "tasks")"

        let status: String
        switch metadata.status {
        case .neverSynchronized:
            status = "Not synced"
        case .current:
            if let refreshDate = metadata.lastSuccessfulRefreshAt {
                status = "Updated \(Self.relativeAge(from: refreshDate, to: now))"
            } else {
                status = "Up to date"
            }
        case .stale, .failed:
            if let refreshDate = metadata.lastSuccessfulRefreshAt {
                status = "Cached \(Self.relativeAge(from: refreshDate, to: now))"
            } else {
                status = "Refresh unavailable"
            }
        }

        summary = "\(taskCountDescription) · \(status)"
        detail = [metadata.statusMessage, metadata.freshnessSummary]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        if seconds < 60 {
            return "now"
        }
        if seconds < 60 * 60 {
            return "\(seconds / 60)m ago"
        }
        if seconds < 24 * 60 * 60 {
            return "\(seconds / (60 * 60))h ago"
        }
        return "\(seconds / (24 * 60 * 60))d ago"
    }
}
