import Foundation

enum GoogleTasksError: Error, Equatable, Sendable {
    case configurationMissing
    case browserLaunchFailed
    case callbackListenerFailed
    case invalidAuthorizationCallback
    case authorizationDenied
    case oauthClientRejected
    case oauthClientSecretRequired
    case oauthAuthorizationCodeRejected
    case oauthVerifierRejected
    case oauthRedirectRejected
    case oauthMalformedRequest
    case oauthRequestRejected
    case offlineCredentialMissing
    case insufficientGrantedScopes
    case credentialStoreFailed
    case authenticationRequired
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed
    case transportFailure
    case persistenceFailure
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .transportFailure:
            return true
        case let .httpStatus(statusCode):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        default:
            return false
        }
    }

    var userMessage: String {
        switch self {
        case .configurationMissing:
            return "Google Tasks needs its Desktop OAuth client configuration."
        case .browserLaunchFailed:
            return "The Google sign-in page could not be opened."
        case .callbackListenerFailed:
            return "Nudge could not start the local Google sign-in callback."
        case .invalidAuthorizationCallback:
            return "The Google sign-in response could not be validated."
        case .authorizationDenied:
            return "Google Tasks access was not granted."
        case .oauthClientRejected:
            return "Google rejected the OAuth client. Confirm the configured client is a Desktop app."
        case .oauthClientSecretRequired:
            return "Google required the configured Desktop OAuth client secret."
        case .oauthAuthorizationCodeRejected:
            return "Google rejected the authorization code. Please start sign-in again."
        case .oauthVerifierRejected:
            return "Google rejected sign-in verification. Please start sign-in again."
        case .oauthRedirectRejected:
            return "Google rejected Nudge's local sign-in callback. Confirm the OAuth client is a Desktop app."
        case .oauthMalformedRequest:
            return "Google rejected the OAuth request format. Please try signing in again."
        case .oauthRequestRejected:
            return "Google rejected the token exchange request. Please try signing in again."
        case .offlineCredentialMissing:
            return "Google did not return an offline credential. Remove Nudge's Google access, then sign in again."
        case .insufficientGrantedScopes:
            return "Google did not grant every permission Nudge requested. Existing cached data and credentials were preserved."
        case .credentialStoreFailed:
            return "Google credentials could not be accessed securely."
        case .authenticationRequired:
            return "Google Tasks needs you to sign in again."
        case .persistenceFailure:
            return "The refreshed tasks could not be saved. Cached tasks remain visible."
        case .cancelled:
            return "Google Tasks refresh was cancelled."
        case .invalidResponse, .httpStatus, .decodingFailed, .transportFailure:
            return "Google Tasks could not be refreshed. Cached tasks remain visible."
        }
    }

    static func normalized(_ error: Error) -> GoogleTasksError {
        if let googleTasksError = error as? GoogleTasksError {
            return googleTasksError
        }
        if let googleOAuthError = error as? GoogleOAuthError {
            switch googleOAuthError {
            case .configurationMissing:
                return .configurationMissing
            case .credentialStoreFailed:
                return .credentialStoreFailed
            case .authenticationRequired, .insufficientGrantedScopes:
                return .authenticationRequired
            case .cancelled:
                return .cancelled
            case .transportFailure:
                return .transportFailure
            case let .httpStatus(statusCode):
                return .httpStatus(statusCode)
            case .decodingFailed:
                return .decodingFailed
            default:
                return .invalidResponse
            }
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        if error is URLError {
            return .transportFailure
        }
        return .invalidResponse
    }
}
