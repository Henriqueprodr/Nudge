import Foundation

struct SyncMetadata: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case neverSynchronized
        case current
        case stale
        case failed
    }

    var status: Status
    var lastAttemptAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var statusMessage: String?

    static let initial = SyncMetadata(
        status: .neverSynchronized,
        lastAttemptAt: nil,
        lastSuccessfulRefreshAt: nil,
        statusMessage: nil
    )

    var freshnessSummary: String {
        let stateDescription: String
        switch status {
        case .neverSynchronized:
            stateDescription = "Never synchronized"
        case .current:
            stateDescription = "Current"
        case .stale:
            stateDescription = "Stale cached data; provider may be offline"
        case .failed:
            stateDescription = "Provider offline or unavailable"
        }
        guard let lastSuccessfulRefreshAt else {
            return "\(stateDescription) · no successful refresh yet"
        }
        return "\(stateDescription) · last success \(lastSuccessfulRefreshAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
