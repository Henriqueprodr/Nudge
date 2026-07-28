import Foundation

struct OAuthCallbackValidator: Sendable {
    func authorizationCode(
        from callbackURL: URL,
        expectedState: String,
        redirectURL: URL
    ) throws -> String {
        guard
            callbackURL.scheme?.lowercased() == redirectURL.scheme?.lowercased(),
            callbackURL.host?.lowercased() == redirectURL.host?.lowercased(),
            callbackURL.port == redirectURL.port,
            normalizedPath(callbackURL.path) == normalizedPath(redirectURL.path),
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else {
            throw GoogleOAuthError.invalidAuthorizationCallback
        }

        let queryValues = Dictionary(
            components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        guard queryValues["state"] == expectedState else {
            throw GoogleOAuthError.invalidAuthorizationCallback
        }
        if queryValues["error"] != nil {
            throw GoogleOAuthError.authorizationDenied
        }
        guard let code = queryValues["code"], !code.isEmpty else {
            throw GoogleOAuthError.invalidAuthorizationCallback
        }
        return code
    }

    private func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}
