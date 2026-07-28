import Foundation

struct ReminderOccurrenceID: Codable, Hashable, Sendable {
    enum SourceKind: String, Codable, Hashable, Sendable {
        case local
        case calendar
        case task
    }

    let sourceKind: SourceKind
    let sourceIdentifier: String
    let occurrenceDate: Date
    let revision: String?
}
