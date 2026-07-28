import Foundation

enum TaskPriority: String, CaseIterable, Codable, Hashable, Sendable {
    case high
    case medium
    case low
    case none

    var displayName: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        case .none:
            return "None"
        }
    }

    var sortRank: Int {
        switch self {
        case .high:
            return 0
        case .medium:
            return 1
        case .low:
            return 2
        case .none:
            return 3
        }
    }
}
