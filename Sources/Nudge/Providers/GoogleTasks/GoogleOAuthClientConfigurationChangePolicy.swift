import Foundation

struct GoogleOAuthClientConfigurationChangePolicy {
    static func canModify(
        isTasksAuthenticated: Bool,
        hasStoredGoogleCredential: Bool,
        providerOperationInProgress: Bool
    ) -> Bool {
        !isTasksAuthenticated &&
            !hasStoredGoogleCredential &&
            !providerOperationInProgress
    }
}
