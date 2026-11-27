import Foundation
import XCTest
@testable import Nudge

final class GoogleSessionLongevityTests: XCTestCase {
    private let signInDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testSevenDaySessionIsAttributedToTestingMode() {
        let record = GoogleSessionEndRecord(
            endedAt: signInDate.addingTimeInterval(7 * 24 * 60 * 60 + 3 * 60 * 60),
            signedInAt: signInDate
        )

        XCTAssertTrue(record.matchesTestingModeExpiry)
        XCTAssertTrue(record.explanation().contains("Testing mode"))
    }

    func testOtherSessionLengthsGetANeutralExplanation() {
        let record = GoogleSessionEndRecord(
            endedAt: signInDate.addingTimeInterval(30 * 24 * 60 * 60),
            signedInAt: signInDate
        )

        XCTAssertFalse(record.matchesTestingModeExpiry)
        let explanation = record.explanation(
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertTrue(explanation.hasPrefix("Google ended Nudge's session on"))
        XCTAssertFalse(explanation.contains("Testing"))
    }

    func testUnknownSignInDateNeverClaimsTestingMode() {
        let record = GoogleSessionEndRecord(endedAt: signInDate, signedInAt: nil)
        XCTAssertNil(record.sessionLifetime)
        XCTAssertFalse(record.matchesTestingModeExpiry)
    }

    func testLegacyStoredCredentialWithoutSignInDateStillDecodes() throws {
        let legacyJSON = """
        {"accessToken":"a","refreshToken":"r","expirationDate":0,"scope":"s","tokenType":"Bearer"}
        """
        let credential = try JSONDecoder().decode(
            GoogleOAuthCredential.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertNil(credential.signedInAt)
    }

    @MainActor
    func testRefreshKeepsOriginalSignInDate() async throws {
        let transport = SessionQueueTransport(bodies: [
            (200, #"{"access_token":"fresh","expires_in":3600,"token_type":"Bearer"}"#),
        ])
        let client = GoogleOAuthClient(transport: transport, now: { Date() })
        let credential = GoogleOAuthCredential(
            accessToken: "old",
            refreshToken: "refresh",
            expirationDate: .distantPast,
            scope: GoogleOAuthConfiguration.tasksScope,
            tokenType: "Bearer",
            signedInAt: signInDate
        )

        let refreshed = try await client.refreshAccessToken(
            credential: credential,
            configuration: GoogleOAuthConfiguration(clientID: "desktop-client")
        )

        XCTAssertEqual(refreshed.signedInAt, signInDate)
        XCTAssertEqual(refreshed.accessToken, "fresh")
    }

    @MainActor
    func testInvalidGrantRecordsSessionEndAndExplainsIt() async {
        let endDate = signInDate.addingTimeInterval(7 * 24 * 60 * 60)
        let credentialStore = InMemoryGoogleCredentialStore(
            credential: GoogleOAuthCredential(
                accessToken: "old",
                refreshToken: "refresh",
                expirationDate: .distantPast,
                scope: GoogleOAuthConfiguration.tasksScope,
                tokenType: "Bearer",
                signedInAt: signInDate
            )
        )
        let sessionEndStore = InMemoryGoogleSessionEndStore()
        let service = GoogleOAuthService(
            configurationProvider: {
                GoogleOAuthConfiguration(clientID: "desktop-client", clientSecret: "secret")
            },
            clientSecretStore: InMemoryGoogleOAuthClientSecretStore(),
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(
                transport: SessionQueueTransport(bodies: [(400, #"{"error":"invalid_grant"}"#)])
            ),
            browserOpener: SystemBrowserOpener(),
            callbackSessionFactory: { LoopbackOAuthCallbackSession() },
            sessionEndStore: sessionEndStore,
            now: { endDate }
        )

        XCTAssertEqual(service.signedInSince, signInDate)
        do {
            _ = try await service.validAccessToken()
            XCTFail("Expected authentication to be required")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .authenticationRequired)
        }

        XCTAssertNil(credentialStore.credential)
        XCTAssertEqual(
            sessionEndStore.record,
            GoogleSessionEndRecord(endedAt: endDate, signedInAt: signInDate)
        )
        XCTAssertTrue(service.sessionEndExplanation?.contains("Testing mode") == true)
    }

    @MainActor
    func testInvalidatedAccessTokenForcesRefreshWithoutDiscardingCredential() async throws {
        let credentialStore = InMemoryGoogleCredentialStore(
            credential: GoogleOAuthCredential(
                accessToken: "stale-but-unexpired",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3_000),
                scope: GoogleOAuthConfiguration.tasksScope,
                tokenType: "Bearer",
                signedInAt: signInDate
            )
        )
        let transport = SessionQueueTransport(bodies: [
            (200, #"{"access_token":"fresh","expires_in":3600,"token_type":"Bearer"}"#),
        ])
        let service = GoogleOAuthService(
            configurationProvider: {
                GoogleOAuthConfiguration(clientID: "desktop-client", clientSecret: "secret")
            },
            clientSecretStore: InMemoryGoogleOAuthClientSecretStore(),
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: transport),
            browserOpener: SystemBrowserOpener(),
            callbackSessionFactory: { LoopbackOAuthCallbackSession() }
        )

        let first = try await service.validAccessToken()
        XCTAssertEqual(first, "stale-but-unexpired")
        XCTAssertEqual(transport.requestCount, 0)

        service.invalidateAccessToken()
        let second = try await service.validAccessToken()

        XCTAssertEqual(second, "fresh")
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(credentialStore.credential?.refreshToken, "refresh")
        XCTAssertEqual(credentialStore.credential?.signedInAt, signInDate)
    }
}

@MainActor
private final class InMemoryGoogleSessionEndStore: GoogleSessionEndStore {
    private(set) var record: GoogleSessionEndRecord?

    func loadRecord() -> GoogleSessionEndRecord? {
        record
    }

    func saveRecord(_ record: GoogleSessionEndRecord) {
        self.record = record
    }

    func clearRecord() {
        record = nil
    }
}

@MainActor
private final class SessionQueueTransport: HTTPTransport {
    private var bodies: [(Int, String)]
    private(set) var requestCount = 0

    init(bodies: [(Int, String)]) {
        self.bodies = bodies
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        guard !bodies.isEmpty, let url = request.url else {
            throw URLError(.badServerResponse)
        }
        let (status, body) = bodies.removeFirst()
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
