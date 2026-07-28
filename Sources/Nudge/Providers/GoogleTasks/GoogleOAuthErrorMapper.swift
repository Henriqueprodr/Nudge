import Foundation

enum GoogleOAuthErrorMapper {
    static func map(
        error: String,
        description: String?,
        grantType: String?
    ) -> GoogleOAuthError? {
        switch error {
        case "invalid_client", "unauthorized_client":
            return .oauthClientRejected
        case "redirect_uri_mismatch":
            return .oauthRedirectRejected
        case "invalid_grant" where grantType == "refresh_token":
            return .authenticationRequired
        case "invalid_grant":
            return category(for: description) ?? .oauthAuthorizationCodeRejected
        case "invalid_request":
            return category(for: description) ?? .oauthRequestRejected
        case "unsupported_grant_type":
            return .oauthMalformedRequest
        default:
            return nil
        }
    }

    private static func category(for description: String?) -> GoogleOAuthError? {
        guard let description else {
            return nil
        }
        let normalized = description.lowercased()

        if normalized.contains("client secret") || normalized.contains("client_secret") {
            return .oauthClientSecretRequired
        }
        if normalized.contains("client_id") {
            return .oauthClientRejected
        }
        if normalized.contains("redirect_uri") || normalized.contains("redirect uri") {
            return .oauthRedirectRejected
        }
        if normalized.contains("code_verifier") || normalized.contains("code verifier") || normalized.contains("pkce") {
            return .oauthVerifierRejected
        }
        if normalized.contains("authorization code") || normalized.contains("parameter: code") || normalized.contains("parameter 'code'") {
            return .oauthAuthorizationCodeRejected
        }
        if normalized.contains("grant_type") || normalized.contains("grant type") || normalized.contains("form body") || normalized.contains("urlencoded") {
            return .oauthMalformedRequest
        }
        return nil
    }
}
