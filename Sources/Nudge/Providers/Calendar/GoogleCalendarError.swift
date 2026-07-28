import Foundation

enum GoogleCalendarError: Error, Equatable, Sendable {
    case authenticationRequired
    case authorizationRequired
    case invalidResponse
    case decodingFailed
    case transportFailure
    case httpStatus(Int)
    case quotaLimited
    case snapshotTooLarge
    case persistenceFailure
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .transportFailure, .quotaLimited:
            true
        case let .httpStatus(statusCode):
            statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        default:
            false
        }
    }

    var userMessage: String {
        switch self {
        case .authenticationRequired, .authorizationRequired:
            "Google Calendar needs additional account permission. Cached reminders remain available."
        case .snapshotTooLarge:
            "The Calendar snapshot exceeded Nudge's safe cache limit. Existing reminders were preserved."
        case .persistenceFailure:
            "Refreshed Calendar data could not be saved. Existing reminders were preserved."
        case .cancelled:
            "Google Calendar refresh was cancelled."
        case .quotaLimited:
            "Google Calendar is temporarily rate limited. Cached reminders remain available."
        case .invalidResponse, .decodingFailed, .transportFailure, .httpStatus:
            "Google Calendar could not be refreshed. Cached reminders remain available."
        }
    }

    static func normalized(_ error: Error) -> GoogleCalendarError {
        if let error = error as? GoogleCalendarError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        if error is URLError { return .transportFailure }
        return .invalidResponse
    }
}
