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
}

extension GoogleTasksAuthenticating {
    var hasBundledClientSecret: Bool {
        false
    }
}

@MainActor
protocol GoogleScopeAuthenticating: AnyObject {
    var isClientIDConfigured: Bool { get }
    var isConfigured: Bool { get }
    func hasStoredCredential(requiredScopes: Set<String>) throws -> Bool
    func signIn(requestingFullScopeUnion scopes: Set<String>) async throws
    func validAccessToken(requiredScopes: Set<String>) async throws -> String
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
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.configurationProvider = configurationProvider
        self.clientSecretStore = clientSecretStore
        self.credentialStore = credentialStore
        self.oauthClient = oauthClient
        self.browserOpener = browserOpener
        self.callbackSessionFactory = callbackSessionFactory
        self.callbackValidator = callbackValidator
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
                try? deleteCredential()
            }
            throw normalizedError
        }
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
