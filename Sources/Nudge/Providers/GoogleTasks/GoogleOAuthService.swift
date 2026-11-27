import Foundation

@MainActor
protocol GoogleTasksAuthenticating: AnyObject {
    var isClientIDConfigured: Bool { get }
    var isConfigured: Bool { get }
    var hasBundledClientSecret: Bool { get }
    func hasStoredClientSecret() throws -> Bool
    func saveClientSecret(_ clientSecret: String) throws
    func deleteClientSecret() throws
    func hasStoredCredential() throws -> Bool
    func signIn() async throws
    func signOut() throws
    func validAccessToken() async throws -> String
    /// Forces the next `validAccessToken()` to refresh. Called after an API returns 401 so a
    /// stale access token never causes the long-lived refresh token to be discarded.
    func invalidateAccessToken()
    /// When the stored credential's interactive sign-in happened, if known.
    var signedInSince: Date? { get }
    /// A human explanation of the last time Google ended the session, if it did.
    var sessionEndExplanation: String? { get }
}

extension GoogleTasksAuthenticating {
    var hasBundledClientSecret: Bool {
        false
    }

    func invalidateAccessToken() {}

    var signedInSince: Date? {
        nil
    }

    var sessionEndExplanation: String? {
        nil
    }
}

@MainActor
protocol GoogleScopeAuthenticating: AnyObject {
    var isClientIDConfigured: Bool { get }
    var isConfigured: Bool { get }
    func hasStoredCredential(requiredScopes: Set<String>) throws -> Bool
    func signIn(requestingFullScopeUnion scopes: Set<String>) async throws
    func validAccessToken(requiredScopes: Set<String>) async throws -> String
    func invalidateAccessToken()
}

extension GoogleScopeAuthenticating {
    func invalidateAccessToken() {}
}

@MainActor
final class GoogleOAuthService: GoogleTasksAuthenticating, GoogleScopeAuthenticating {
    typealias ConfigurationProvider = @MainActor () throws -> GoogleOAuthConfiguration
    typealias CallbackSessionFactory = @MainActor () -> any OAuthCallbackSession

    private let configurationProvider: ConfigurationProvider
    private let clientSecretStore: any GoogleOAuthClientSecretStore
    private let credentialStore: any GoogleCredentialStore
    private let oauthClient: GoogleOAuthClient
    private let browserOpener: any SystemBrowserOpening
    private let callbackSessionFactory: CallbackSessionFactory
    private let callbackValidator: OAuthCallbackValidator
    private let sessionEndStore: (any GoogleSessionEndStore)?
    private let usesOwnOAuthClient: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private var hasLoadedClientSecret = false
    private var cachedClientSecret: String?
    private var hasLoadedCredential = false
    private var cachedCredential: GoogleOAuthCredential?

    init(
        configurationProvider: @escaping ConfigurationProvider,
        clientSecretStore: any GoogleOAuthClientSecretStore,
        credentialStore: any GoogleCredentialStore,
        oauthClient: GoogleOAuthClient,
        browserOpener: any SystemBrowserOpening,
        callbackSessionFactory: @escaping CallbackSessionFactory,
        callbackValidator: OAuthCallbackValidator = OAuthCallbackValidator(),
        sessionEndStore: (any GoogleSessionEndStore)? = nil,
        usesOwnOAuthClient: @escaping @MainActor () -> Bool = { true },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.configurationProvider = configurationProvider
        self.clientSecretStore = clientSecretStore
        self.credentialStore = credentialStore
        self.oauthClient = oauthClient
        self.browserOpener = browserOpener
        self.callbackSessionFactory = callbackSessionFactory
        self.callbackValidator = callbackValidator
        self.sessionEndStore = sessionEndStore
        self.usesOwnOAuthClient = usesOwnOAuthClient
        self.now = now
    }

    var isClientIDConfigured: Bool {
        (try? configurationProvider()) != nil
    }

    var isConfigured: Bool {
        isClientIDConfigured
    }

    var hasBundledClientSecret: Bool {
        guard let configuration = try? configurationProvider() else {
            return false
        }
        return configuration.clientSecret?.isEmpty == false
    }

    func hasStoredClientSecret() throws -> Bool {
        try loadClientSecret() != nil
    }

    func saveClientSecret(_ clientSecret: String) throws {
        try clientSecretStore.saveClientSecret(clientSecret)
        cachedClientSecret = clientSecret
        hasLoadedClientSecret = true
    }

    func deleteClientSecret() throws {
        try clientSecretStore.deleteClientSecret()
        cachedClientSecret = nil
        hasLoadedClientSecret = true
    }

    func hasStoredCredential() throws -> Bool {
        try hasStoredCredential(requiredScopes: [GoogleOAuthConfiguration.tasksScope])
    }

    func hasStoredCredential(requiredScopes: Set<String>) throws -> Bool {
        guard let credential = try loadCredential() else {
            return false
        }
        return credentialHasScopes(credential, requiredScopes: requiredScopes)
    }

    func signIn() async throws {
        try await signIn(
            requestingFullScopeUnion: GoogleOAuthConfiguration.requiredScopeUnion
        )
    }

    func signIn(requestingFullScopeUnion scopes: Set<String>) async throws {
        let configuration = try configuredClientForExplicitSignIn(requesting: scopes)
        let pkce = try PKCEGenerator.generate()
        let state = try PKCEGenerator.randomState()
        let callbackSession = callbackSessionFactory()
        let redirectURL = try await callbackSession.start()
        defer {
            callbackSession.stop()
        }

        let authorizationURL = try configuration.authorizationURL(
            redirectURL: redirectURL,
            codeChallenge: pkce.challenge,
            state: state
        )
        guard browserOpener.open(authorizationURL) else {
            throw GoogleOAuthError.browserLaunchFailed
        }

        let callbackURL = try await callbackSession.waitForCallback()
        let authorizationCode = try callbackValidator.authorizationCode(
            from: callbackURL,
            expectedState: state,
            redirectURL: redirectURL
        )
        let credential = try await oauthClient.exchangeAuthorizationCode(
            authorizationCode,
            codeVerifier: pkce.verifier,
            redirectURL: redirectURL,
            configuration: configuration
        )
        guard credentialHasScopes(credential, requiredScopes: scopes) else {
            throw GoogleOAuthError.insufficientGrantedScopes
        }
        try saveCredential(credential)
        sessionEndStore?.clearRecord()
    }

    func signOut() throws {
        try deleteCredential()
    }

    func validAccessToken() async throws -> String {
        try await validAccessToken(requiredScopes: [GoogleOAuthConfiguration.tasksScope])
    }

    func validAccessToken(requiredScopes: Set<String>) async throws -> String {
        guard let credential = try loadCredential(),
              credentialHasScopes(credential, requiredScopes: requiredScopes) else {
            throw GoogleOAuthError.authenticationRequired
        }
        if credential.hasUsableAccessToken(at: now()) {
            return credential.accessToken
        }

        do {
            let refreshedCredential = try await oauthClient.refreshAccessToken(
                credential: credential,
                configuration: try configuredClient(requesting: requiredScopes)
            )
            try saveCredential(refreshedCredential)
            return refreshedCredential.accessToken
        } catch {
            let normalizedError = GoogleOAuthError.normalized(error)
            if normalizedError == .authenticationRequired {
                sessionEndStore?.saveRecord(
                    GoogleSessionEndRecord(endedAt: now(), signedInAt: credential.signedInAt)
                )
                try? deleteCredential()
            }
            throw normalizedError
        }
    }

    func invalidateAccessToken() {
        guard hasLoadedCredential, var credential = cachedCredential else { return }
        credential.expirationDate = .distantPast
        cachedCredential = credential
    }

    var signedInSince: Date? {
        (try? loadCredential())?.signedInAt
    }

    var sessionEndExplanation: String? {
        sessionEndStore?.loadRecord()?.explanation(usesOwnOAuthClient: usesOwnOAuthClient())
    }

    private func configuredClient(requesting scopes: Set<String>) throws -> GoogleOAuthConfiguration {
        let configuration = try configurationProvider()
        if configuration.clientSecret?.isEmpty == false {
            return configuration.requesting(scopes)
        }
        return configuration.requesting(scopes, clientSecret: try loadClientSecret())
    }

    private func configuredClientForExplicitSignIn(
        requesting scopes: Set<String>
    ) throws -> GoogleOAuthConfiguration {
        let configuration = try configurationProvider()
        if configuration.clientSecret?.isEmpty == false {
            return configuration.requesting(scopes)
        }
        if let currentClientSecret = try loadClientSecret() {
            return configuration.requesting(scopes, clientSecret: currentClientSecret)
        }
        return configuration.requesting(scopes)
    }

    private func credentialHasScopes(
        _ credential: GoogleOAuthCredential,
        requiredScopes: Set<String>
    ) -> Bool {
        let grantedScopes = Set(credential.scope.split(separator: " ").map(String.init))
        return requiredScopes.isSubset(of: grantedScopes)
    }

    private func loadClientSecret() throws -> String? {
        if hasLoadedClientSecret {
            return cachedClientSecret
        }
        let clientSecret = try clientSecretStore.loadClientSecret()
        cachedClientSecret = clientSecret
        hasLoadedClientSecret = true
        return clientSecret
    }

    private func loadCredential() throws -> GoogleOAuthCredential? {
        if hasLoadedCredential {
            return cachedCredential
        }
        let credential = try credentialStore.loadCredential()
        cachedCredential = credential
        hasLoadedCredential = true
        return credential
    }

    private func saveCredential(_ credential: GoogleOAuthCredential) throws {
        try credentialStore.saveCredential(credential)
        cachedCredential = credential
        hasLoadedCredential = true
    }

    private func deleteCredential() throws {
        try credentialStore.deleteCredential()
        cachedCredential = nil
        hasLoadedCredential = true
    }
}
