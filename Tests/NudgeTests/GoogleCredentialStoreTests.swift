import Foundation
import XCTest
@testable import Nudge

final class GoogleCredentialStoreTests: XCTestCase {
    @MainActor
    func testCredentialStoreAbstractionRoundTripsAndDeletesWithoutLoggingSecrets() throws {
        let store = InMemoryGoogleCredentialStore()
        let credential = GoogleOAuthCredential(
            accessToken: "access-token-value",
            refreshToken: "refresh-token-value",
            expirationDate: Date(timeIntervalSince1970: 10_000),
            scope: GoogleOAuthConfiguration.tasksScope,
            tokenType: "Bearer"
        )

        XCTAssertNil(try store.loadCredential())
        try store.saveCredential(credential)
        XCTAssertEqual(try store.loadCredential(), credential)
        try store.deleteCredential()
        XCTAssertNil(try store.loadCredential())
    }

    @MainActor
    func testClientSecretStoreRoundTripsAndDeletesSeparatelyFromOAuthTokens() throws {
        let clientSecretStore = InMemoryGoogleOAuthClientSecretStore()
        let credentialStore = InMemoryGoogleCredentialStore()
        let credential = GoogleOAuthCredential(
            accessToken: "fake-access",
            refreshToken: "fake-refresh",
            expirationDate: Date(timeIntervalSince1970: 10_000),
            scope: GoogleOAuthConfiguration.tasksReadOnlyScope,
            tokenType: "Bearer"
        )

        try clientSecretStore.saveClientSecret("fake-client-secret")
        try credentialStore.saveCredential(credential)
        try credentialStore.deleteCredential()

        XCTAssertEqual(try clientSecretStore.loadClientSecret(), "fake-client-secret")
        XCTAssertNil(try credentialStore.loadCredential())

        try clientSecretStore.deleteClientSecret()
        XCTAssertNil(try clientSecretStore.loadClientSecret())
    }

    func testSuccessfulClientSecretDraftSaveClearsTemporaryPlaintext() {
        var draft = GoogleOAuthClientSecretDraft(value: "fake-client-secret")

        XCTAssertTrue(draft.save { _ in true })
        XCTAssertTrue(draft.value.isEmpty)

        draft.value = "unsaved-fake-secret"
        XCTAssertFalse(draft.save { _ in false })
        XCTAssertEqual(draft.value, "unsaved-fake-secret")
    }

    @MainActor
    func testOAuthServiceReadsEachKeychainValueOnlyOncePerAppRun() async throws {
        let credential = GoogleOAuthCredential(
            accessToken: "cached-access-token",
            refreshToken: "cached-refresh-token",
            expirationDate: Date.distantFuture,
            scope: GoogleOAuthConfiguration.tasksScope,
            tokenType: "Bearer"
        )
        let clientSecretStore = InMemoryGoogleOAuthClientSecretStore(
            clientSecret: "cached-client-secret"
        )
        let credentialStore = InMemoryGoogleCredentialStore(credential: credential)
        let service = GoogleOAuthService(
            configurationProvider: {
                GoogleOAuthConfiguration(clientID: "configured-client-id")
            },
            clientSecretStore: clientSecretStore,
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: URLSessionHTTPTransport()),
            browserOpener: SystemBrowserOpener(),
            callbackSessionFactory: {
                LoopbackOAuthCallbackSession()
            }
        )

        XCTAssertTrue(service.isConfigured)
        XCTAssertTrue(try service.hasStoredClientSecret())
        XCTAssertTrue(service.isConfigured)
        XCTAssertEqual(clientSecretStore.loadCount, 1)
        XCTAssertEqual(clientSecretStore.interactiveLoadCount, 0)

        XCTAssertTrue(try service.hasStoredCredential())
        let accessToken = try await service.validAccessToken()
        XCTAssertEqual(accessToken, "cached-access-token")
        XCTAssertTrue(try service.hasStoredCredential())
        XCTAssertEqual(credentialStore.loadCount, 1)
        XCTAssertEqual(credentialStore.interactiveLoadCount, 0)
    }

    @MainActor
    func testExplicitSignInDoesNotRequireLegacyKeychainInteractionBeforeOpeningGoogle() async throws {
        let clientSecretStore = InMemoryGoogleOAuthClientSecretStore()
        let credentialStore = InMemoryGoogleCredentialStore()
        let transport = PartialScopeOAuthTransport()
        let browser = RecordingOAuthBrowser()
        let callback = CoupledOAuthCallback(browser: browser)
        let service = GoogleOAuthService(
            configurationProvider: { GoogleOAuthConfiguration(clientID: "desktop-client") },
            clientSecretStore: clientSecretStore,
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: transport),
            browserOpener: browser,
            callbackSessionFactory: { callback }
        )

        XCTAssertFalse((try? service.hasStoredClientSecret()) == true)
        XCTAssertFalse((try? service.hasStoredCredential(requiredScopes: [])) == true)
        XCTAssertEqual(clientSecretStore.interactiveLoadCount, 0)
        XCTAssertEqual(credentialStore.interactiveLoadCount, 0)

        do {
            try await service.signIn(
                requestingFullScopeUnion: GoogleOAuthConfiguration.requiredScopeUnion
            )
            XCTFail("Expected the partial-scope fixture to reject consent")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .insufficientGrantedScopes)
        }

        XCTAssertEqual(clientSecretStore.interactiveLoadCount, 0)
        XCTAssertEqual(credentialStore.interactiveLoadCount, 0)
        XCTAssertNotNil(browser.openedURL)
    }

    @MainActor
    func testBundledClientSecretBypassesLegacyKeychainInteraction() async throws {
        let clientSecretStore = InMemoryGoogleOAuthClientSecretStore(
            legacyClientSecret: "legacy-client-secret"
        )
        let credentialStore = InMemoryGoogleCredentialStore()
        let transport = FullScopeOAuthTransport()
        let browser = RecordingOAuthBrowser()
        let callback = CoupledOAuthCallback(browser: browser)
        let service = GoogleOAuthService(
            configurationProvider: {
                GoogleOAuthConfiguration(
                    clientID: "desktop-client",
                    clientSecret: "bundled-client-secret"
                )
            },
            clientSecretStore: clientSecretStore,
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: transport),
            browserOpener: browser,
            callbackSessionFactory: { callback }
        )

        XCTAssertFalse(try service.hasStoredClientSecret())
        XCTAssertTrue(service.hasBundledClientSecret)
        XCTAssertTrue(try clientSecretStore.hasLegacyClientSecret())

        try await service.signIn(
            requestingFullScopeUnion: GoogleOAuthConfiguration.requiredScopeUnion
        )

        XCTAssertEqual(clientSecretStore.interactiveLoadCount, 0)
        XCTAssertEqual(credentialStore.interactiveLoadCount, 0)
        XCTAssertEqual(credentialStore.saveCount, 1)
        XCTAssertFalse(try service.hasStoredClientSecret())
        XCTAssertTrue(try clientSecretStore.hasLegacyClientSecret())
        XCTAssertTrue(transport.receivedClientSecret)
        XCTAssertNotNil(browser.openedURL)
    }

    @MainActor
    func testReadOnlyCredentialRequiresConsentForPhaseFiveMutationScope() async throws {
        let credentialStore = InMemoryGoogleCredentialStore(
            credential: GoogleOAuthCredential(
                accessToken: "read-only-access-token",
                refreshToken: "read-only-refresh-token",
                expirationDate: .distantFuture,
                scope: GoogleOAuthConfiguration.tasksReadOnlyScope,
                tokenType: "Bearer"
            )
        )
        let service = GoogleOAuthService(
            configurationProvider: {
                GoogleOAuthConfiguration(clientID: "configured-client-id")
            },
            clientSecretStore: InMemoryGoogleOAuthClientSecretStore(
                clientSecret: "configured-client-secret"
            ),
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: URLSessionHTTPTransport()),
            browserOpener: SystemBrowserOpener(),
            callbackSessionFactory: {
                LoopbackOAuthCallbackSession()
            }
        )

        XCTAssertFalse(try service.hasStoredCredential())
        do {
            _ = try await service.validAccessToken()
            XCTFail("Expected Phase 5 scope upgrade to require authentication")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .authenticationRequired)
        }
    }

    @MainActor
    func testPartialScopeConsentDoesNotOverwriteExistingTasksCredential() async throws {
        let oldCredential = GoogleOAuthCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expirationDate: .distantFuture,
            scope: GoogleOAuthConfiguration.tasksScope,
            tokenType: "Bearer"
        )
        let credentialStore = InMemoryGoogleCredentialStore(credential: oldCredential)
        let transport = PartialScopeOAuthTransport()
        let browser = RecordingOAuthBrowser()
        let callback = CoupledOAuthCallback(browser: browser)
        let service = GoogleOAuthService(
            configurationProvider: { GoogleOAuthConfiguration(clientID: "desktop-client") },
            clientSecretStore: InMemoryGoogleOAuthClientSecretStore(),
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: transport),
            browserOpener: browser,
            callbackSessionFactory: { callback }
        )

        do {
            try await service.signIn(
                requestingFullScopeUnion: GoogleOAuthConfiguration.requiredScopeUnion
            )
            XCTFail("Expected incomplete scope rejection")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .insufficientGrantedScopes)
        }

        XCTAssertEqual(credentialStore.credential, oldCredential)
        XCTAssertEqual(credentialStore.saveCount, 0)
        let query = URLComponents(url: try XCTUnwrap(browser.openedURL), resolvingAgainstBaseURL: false)
        XCTAssertEqual(query?.queryItems?.first(where: { $0.name == "prompt" })?.value, "consent")
    }
}

@MainActor
final class InMemoryGoogleOAuthClientSecretStore: GoogleOAuthClientSecretStore {
    private var clientSecret: String?
    private var legacyClientSecret: String?
    private(set) var loadCount = 0
    private(set) var interactiveLoadCount = 0

    init(clientSecret: String? = nil, legacyClientSecret: String? = nil) {
        self.clientSecret = clientSecret
        self.legacyClientSecret = legacyClientSecret
    }

    func loadClientSecret() throws -> String? {
        loadCount += 1
        return clientSecret
    }

    func loadClientSecretAllowingUserInteraction() throws -> String? {
        interactiveLoadCount += 1
        if clientSecret == nil, let legacyClientSecret {
            clientSecret = legacyClientSecret
        }
        return clientSecret
    }

    func hasLegacyClientSecret() throws -> Bool {
        legacyClientSecret != nil
    }

    func saveClientSecret(_ clientSecret: String) throws {
        self.clientSecret = clientSecret
    }

    func deleteClientSecret() throws {
        clientSecret = nil
    }
}

@MainActor
final class InMemoryGoogleCredentialStore: GoogleCredentialStore {
    private(set) var credential: GoogleOAuthCredential?
    private(set) var loadCount = 0
    private(set) var interactiveLoadCount = 0
    private(set) var saveCount = 0

    init(credential: GoogleOAuthCredential? = nil) {
        self.credential = credential
    }

    func loadCredential() throws -> GoogleOAuthCredential? {
        loadCount += 1
        return credential
    }

    func loadCredentialAllowingUserInteraction() throws -> GoogleOAuthCredential? {
        interactiveLoadCount += 1
        return credential
    }

    func saveCredential(_ credential: GoogleOAuthCredential) throws {
        saveCount += 1
        self.credential = credential
    }

    func deleteCredential() throws {
        credential = nil
    }
}

@MainActor
private final class PartialScopeOAuthTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = """
        {"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"scope":"https://www.googleapis.com/auth/tasks","token_type":"Bearer"}
        """
        return (
            Data(body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

@MainActor
private final class FullScopeOAuthTransport: HTTPTransport {
    private(set) var receivedClientSecret = false

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let bodyText = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        receivedClientSecret = bodyText.contains("client_secret=")
        let scopes = GoogleOAuthConfiguration.requiredScopeUnion.sorted().joined(separator: " ")
        let body = """
        {"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"scope":"\(scopes)","token_type":"Bearer"}
        """
        return (
            Data(body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

@MainActor
private final class RecordingOAuthBrowser: SystemBrowserOpening {
    private(set) var openedURL: URL?
    func open(_ url: URL) -> Bool {
        openedURL = url
        return true
    }
}

@MainActor
private final class CoupledOAuthCallback: OAuthCallbackSession {
    private unowned let browser: RecordingOAuthBrowser
    private let redirectURL = URL(string: "http://127.0.0.1:54321")!

    init(browser: RecordingOAuthBrowser) { self.browser = browser }
    func start() async throws -> URL { redirectURL }
    func waitForCallback() async throws -> URL {
        let state = URLComponents(url: browser.openedURL!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value
        var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "authorization-code"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
    func stop() {}
}
