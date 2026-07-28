import Foundation

enum GoogleOAuthError: Error, Equatable, Sendable {
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
    case cancelled

    var userMessage: String {
        switch self {
        case .configurationMissing:
            return "Google OAuth client configuration is required."
        case .browserLaunchFailed:
            return "The Google sign-in page could not be opened."
        case .callbackListenerFailed:
            return "Nudge could not start the local Google sign-in callback."
        case .invalidAuthorizationCallback:
            return "The Google sign-in response could not be validated."
        case .authorizationDenied:
            return "Google access was not granted."
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
            return "The Google account needs you to sign in again."
        case .cancelled:
            return "Google sign-in was cancelled."
        case .invalidResponse, .httpStatus, .decodingFailed, .transportFailure:
            return "Google sign-in could not be completed."
        }
    }

    static func normalized(_ error: Error) -> GoogleOAuthError {
        if let googleOAuthError = error as? GoogleOAuthError {
            return googleOAuthError
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
