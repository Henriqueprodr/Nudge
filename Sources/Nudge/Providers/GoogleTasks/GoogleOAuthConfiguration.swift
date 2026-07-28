import Foundation

struct GoogleOAuthConfiguration: Equatable, Sendable {
    static let tasksReadOnlyScope = "https://www.googleapis.com/auth/tasks.readonly"
    static let tasksScope = "https://www.googleapis.com/auth/tasks"
    static let calendarListReadOnlyScope =
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    static let calendarEventsReadOnlyScope =
        "https://www.googleapis.com/auth/calendar.events.readonly"
    static let calendarReadScopes: Set<String> = [
        calendarListReadOnlyScope,
        calendarEventsReadOnlyScope,
    ]
    static let requiredScopeUnion: Set<String> = calendarReadScopes.union([tasksScope])

    let clientID: String
    let clientSecret: String?
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let scopes: Set<String>

    var scope: String {
        scopes.sorted().joined(separator: " ")
    }

    init(
        clientID: String,
        clientSecret: String? = nil,
        authorizationEndpoint: URL = URL(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        scopes: Set<String> = GoogleOAuthConfiguration.requiredScopeUnion
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
    }

    static func bundled(
        clientSecret: String? = nil,
        bundle: Bundle = .main
    ) throws -> GoogleOAuthConfiguration {
        let environmentClientID = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"]
            ?? ProcessInfo.processInfo.environment["GOOGLE_TASKS_CLIENT_ID"]
        let bundledClientID = bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String
            ?? bundle.object(forInfoDictionaryKey: "GoogleTasksClientID") as? String
        let clientID = (environmentClientID ?? bundledClientID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentClientSecret = ProcessInfo.processInfo.environment[
            "GOOGLE_OAUTH_CLIENT_SECRET"
        ] ?? ProcessInfo.processInfo.environment["GOOGLE_TASKS_CLIENT_SECRET"]
        let bundledClientSecret = bundle.object(
            forInfoDictionaryKey: "GoogleOAuthClientSecret"
        ) as? String
        let resolvedClientSecret = (clientSecret ?? environmentClientSecret ?? bundledClientSecret ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clientID.isEmpty, !clientID.contains("$(") else {
            throw GoogleOAuthError.configurationMissing
        }
        let usableClientSecret = resolvedClientSecret.isEmpty || resolvedClientSecret.contains("$(")
            ? nil
            : resolvedClientSecret
        return GoogleOAuthConfiguration(clientID: clientID, clientSecret: usableClientSecret)
    }

    func requesting(_ scopes: Set<String>, clientSecret: String? = nil) -> Self {
        GoogleOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret ?? self.clientSecret,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            scopes: scopes
        )
    }

    func authorizationURL(
        redirectURL: URL,
        codeChallenge: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(
            url: authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw GoogleOAuthError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components.url else {
            throw GoogleOAuthError.invalidResponse
        }
        return url
    }
}
