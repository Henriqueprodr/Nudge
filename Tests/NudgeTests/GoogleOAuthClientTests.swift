import Foundation
import XCTest
@testable import Nudge

final class GoogleOAuthClientTests: XCTestCase {
    private static let validVerifier = String(repeating: "v", count: 64)

    @MainActor
    func testAuthorizationCodeExchangeAndExpiredTokenRefreshPreserveRefreshToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let transport = QueueHTTPTransport(responses: [
            .success(
                statusCode: 200,
                body: """
                {
                  "access_token": "first-access",
                  "refresh_token": "long-lived-refresh",
                  "expires_in": 3600,
                  "scope": "https://www.googleapis.com/auth/tasks.readonly",
                  "token_type": "Bearer"
                }
                """
            ),
            .success(
                statusCode: 200,
                body: """
                {
                  "access_token": "refreshed-access",
                  "expires_in": 3600,
                  "scope": "https://www.googleapis.com/auth/tasks.readonly",
                  "token_type": "Bearer"
                }
                """
            ),
        ])
        let client = GoogleOAuthClient(transport: transport, now: { now })
        let configuration = GoogleOAuthConfiguration(clientID: "desktop-client")
        let redirectURL = URL(string: "http://127.0.0.1:54321")!

        let credential = try await client.exchangeAuthorizationCode(
            "4/0A+code=value&next step",
            codeVerifier: Self.validVerifier,
            redirectURL: redirectURL,
            configuration: configuration
        )
        let refreshed = try await client.refreshAccessToken(
            credential: credential,
            configuration: configuration
        )

        XCTAssertEqual(credential.refreshToken, "long-lived-refresh")
        XCTAssertEqual(credential.expirationDate, now.addingTimeInterval(3600))
        XCTAssertEqual(refreshed.accessToken, "refreshed-access")
        XCTAssertEqual(refreshed.refreshToken, "long-lived-refresh")
        XCTAssertTrue(transport.requestBodies[0].contains("code=4%2F0A%2Bcode%3Dvalue%26next+step"))
        XCTAssertTrue(transport.requestBodies[0].contains("code_verifier=\(Self.validVerifier)"))
        XCTAssertTrue(transport.requestBodies[1].contains("grant_type=refresh_token"))
    }

    @MainActor
    func testClientSecretIsFormEncodedForCodeExchangeAndTokenRefresh() async throws {
        let transport = QueueHTTPTransport(responses: [
            .success(
                statusCode: 200,
                body: """
                {
                  "access_token": "first-access",
                  "refresh_token": "long-lived-refresh",
                  "expires_in": 3600,
                  "token_type": "Bearer"
                }
                """
            ),
            .success(
                statusCode: 200,
                body: """
                {
                  "access_token": "refreshed-access",
                  "expires_in": 3600,
                  "token_type": "Bearer"
                }
                """
            ),
        ])
        let client = GoogleOAuthClient(transport: transport)
        let configuration = GoogleOAuthConfiguration(
            clientID: "desktop-client",
            clientSecret: "fake+secret/=& snow"
        )

        let credential = try await client.exchangeAuthorizationCode(
            "authorization-code",
            codeVerifier: Self.validVerifier,
            redirectURL: URL(string: "http://127.0.0.1:54321")!,
            configuration: configuration
        )
        _ = try await client.refreshAccessToken(
            credential: credential,
            configuration: configuration
        )

        let encodedSecret = "client_secret=fake%2Bsecret%2F%3D%26+snow"
        XCTAssertTrue(transport.requestBodies[0].contains(encodedSecret))
        XCTAssertTrue(transport.requestBodies[1].contains(encodedSecret))
    }

    @MainActor
    func testInvalidGrantRequiresReauthentication() async {
        let transport = QueueHTTPTransport(responses: [
            .success(statusCode: 400, body: "{\"error\":\"invalid_grant\"}"),
        ])
        let client = GoogleOAuthClient(transport: transport)
        let credential = GoogleOAuthCredential(
            accessToken: "expired",
            refreshToken: "invalid-refresh",
            expirationDate: .distantPast,
            scope: GoogleOAuthConfiguration.tasksReadOnlyScope,
            tokenType: "Bearer"
        )

        do {
            _ = try await client.refreshAccessToken(
                credential: credential,
                configuration: GoogleOAuthConfiguration(clientID: "desktop-client")
            )
            XCTFail("Expected authenticationRequired")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .authenticationRequired)
        }
    }

    @MainActor
    func testTokenExchangeReportsPrivacySafeOAuthErrors() async {
        let expectedErrors: [(String, GoogleOAuthError)] = [
            ("invalid_client", .oauthClientRejected),
            ("unauthorized_client", .oauthClientRejected),
            ("redirect_uri_mismatch", .oauthRedirectRejected),
            ("invalid_request", .oauthRequestRejected),
        ]

        for (responseError, expectedError) in expectedErrors {
            let transport = QueueHTTPTransport(responses: [
                .success(statusCode: 400, body: "{\"error\":\"\(responseError)\"}"),
            ])
            let client = GoogleOAuthClient(transport: transport)

            do {
                _ = try await client.exchangeAuthorizationCode(
                    "authorization-code",
                    codeVerifier: Self.validVerifier,
                    redirectURL: URL(string: "http://127.0.0.1:54321")!,
                    configuration: GoogleOAuthConfiguration(clientID: "desktop-client")
                )
                XCTFail("Expected \(expectedError)")
            } catch {
                XCTAssertEqual(error as? GoogleOAuthError, expectedError)
            }
        }
    }

    @MainActor
    func testInitialExchangeRequiresOfflineCredential() async {
        let transport = QueueHTTPTransport(responses: [
            .success(
                statusCode: 200,
                body: """
                {
                  "access_token": "short-lived-access",
                  "expires_in": 3600,
                  "scope": "https://www.googleapis.com/auth/tasks.readonly",
                  "token_type": "Bearer"
                }
                """
            ),
        ])
        let client = GoogleOAuthClient(transport: transport)

        do {
            _ = try await client.exchangeAuthorizationCode(
                "authorization-code",
                codeVerifier: Self.validVerifier,
                redirectURL: URL(string: "http://127.0.0.1:54321")!,
                configuration: GoogleOAuthConfiguration(clientID: "desktop-client")
            )
            XCTFail("Expected offlineCredentialMissing")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .offlineCredentialMissing)
        }
    }

    func testFormEncoderEscapesFormReservedCharactersSpacesAndUnicode() {
        let fields = [
            URLQueryItem(name: "code", value: "4/0A+abc=def&ghi jkl"),
            URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:54321"),
            URLQueryItem(name: "unicode", value: "ação ☕️"),
        ]

        XCTAssertEqual(
            String(data: OAuthFormEncoder.encode(fields), encoding: .utf8),
            "code=4%2F0A%2Babc%3Ddef%26ghi+jkl&redirect_uri=http%3A%2F%2F127.0.0.1%3A54321&unicode=a%C3%A7%C3%A3o+%E2%98%95%EF%B8%8F"
        )
    }

    func testAuthorizationCodePreflightRequiresOneNonemptyValueForEveryField() {
        let expectedErrors: [String: GoogleOAuthError] = [
            "client_id": .oauthClientRejected,
            "code": .oauthAuthorizationCodeRejected,
            "code_verifier": .oauthVerifierRejected,
            "grant_type": .oauthMalformedRequest,
            "redirect_uri": .oauthRedirectRejected,
        ]

        for (name, expectedError) in expectedErrors {
            let validFields = authorizationCodeFields()

            XCTAssertThrowsError(
                try OAuthTokenRequestValidator.validateAuthorizationCode(
                    validFields.filter { $0.name != name }
                )
            ) { error in
                XCTAssertEqual(error as? GoogleOAuthError, expectedError)
            }

            XCTAssertThrowsError(
                try OAuthTokenRequestValidator.validateAuthorizationCode(
                    validFields.map {
                        $0.name == name ? URLQueryItem(name: name, value: "   ") : $0
                    }
                )
            ) { error in
                XCTAssertEqual(error as? GoogleOAuthError, expectedError)
            }

            let duplicatedFields = validFields + [validFields.first { $0.name == name }!]
            XCTAssertThrowsError(
                try OAuthTokenRequestValidator.validateAuthorizationCode(duplicatedFields)
            ) { error in
                XCTAssertEqual(error as? GoogleOAuthError, expectedError)
            }
        }
    }

    func testAuthorizationCodePreflightEnforcesPKCEAndRootLoopbackRedirect() throws {
        for invalidVerifier in [
            String(repeating: "v", count: 42),
            String(repeating: "v", count: 129),
            String(repeating: "v", count: 63) + "+",
        ] {
            XCTAssertThrowsError(
                try OAuthTokenRequestValidator.validateAuthorizationCode(
                    authorizationCodeFields(verifier: invalidVerifier)
                )
            ) { error in
                XCTAssertEqual(error as? GoogleOAuthError, .oauthVerifierRejected)
            }
        }

        let invalidRedirects = [
            "https://127.0.0.1:54321",
            "http://localhost:54321",
            "http://127.0.0.1",
            "http://127.0.0.1:80",
            "http://127.0.0.1:54321/oauth/callback",
            "http://127.0.0.1:54321/?query=value",
        ]
        for redirect in invalidRedirects {
            XCTAssertThrowsError(
                try OAuthTokenRequestValidator.validateAuthorizationCode(
                    authorizationCodeFields(redirect: redirect)
                )
            ) { error in
                XCTAssertEqual(error as? GoogleOAuthError, .oauthRedirectRejected)
            }
        }

        XCTAssertNoThrow(
            try OAuthTokenRequestValidator.validateAuthorizationCode(
                authorizationCodeFields(redirect: "http://127.0.0.1:54321/")
            )
        )
    }

    func testTokenPreflightAllowsOneClientSecretAndRejectsEmptyOrDuplicateValues() {
        let secretField = URLQueryItem(name: "client_secret", value: "fake-secret")
        let fields = authorizationCodeFields()

        XCTAssertNoThrow(
            try OAuthTokenRequestValidator.validateAuthorizationCode(fields + [secretField])
        )
        XCTAssertThrowsError(
            try OAuthTokenRequestValidator.validateAuthorizationCode(
                fields + [URLQueryItem(name: "client_secret", value: "")]
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .oauthMalformedRequest)
        }
        XCTAssertThrowsError(
            try OAuthTokenRequestValidator.validateAuthorizationCode(
                fields + [secretField, secretField]
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .oauthMalformedRequest)
        }

        let refreshFields = [
            URLQueryItem(name: "client_id", value: "desktop-client"),
            URLQueryItem(name: "refresh_token", value: "fake-refresh"),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        XCTAssertNoThrow(
            try OAuthTokenRequestValidator.validateRefreshToken(refreshFields + [secretField])
        )
        XCTAssertThrowsError(
            try OAuthTokenRequestValidator.validateRefreshToken(
                refreshFields + [secretField, secretField]
            )
        )
    }

    @MainActor
    func testGoogleDiagnosticDescriptionsMapToFixedNonleakingErrors() async {
        let sensitiveMarker = ["ya29", "fake-token-like-secret"].joined(separator: ".")
        let cases: [(String, GoogleOAuthError)] = [
            ("Missing required parameter: code. \(sensitiveMarker)", .oauthAuthorizationCodeRejected),
            ("Invalid code_verifier. \(sensitiveMarker)", .oauthVerifierRejected),
            ("redirect_uri mismatch. \(sensitiveMarker)", .oauthRedirectRejected),
            ("client_secret is missing. \(sensitiveMarker)", .oauthClientSecretRequired),
            ("Unsupported grant_type in malformed form body. \(sensitiveMarker)", .oauthMalformedRequest),
            ("Request could not be processed. \(sensitiveMarker)", .oauthRequestRejected),
        ]

        for (description, expectedError) in cases {
            let responseObject = [
                "error": "invalid_request",
                "error_description": description,
            ]
            let responseData = try! JSONSerialization.data(withJSONObject: responseObject)
            let transport = QueueHTTPTransport(responses: [
                .success(statusCode: 400, data: responseData),
            ])
            let client = GoogleOAuthClient(transport: transport)

            do {
                _ = try await client.exchangeAuthorizationCode(
                    "authorization-code",
                    codeVerifier: Self.validVerifier,
                    redirectURL: URL(string: "http://127.0.0.1:54321")!,
                    configuration: GoogleOAuthConfiguration(clientID: "desktop-client")
                )
                XCTFail("Expected a categorized OAuth error")
            } catch {
                let typedError = error as? GoogleOAuthError
                XCTAssertEqual(typedError, expectedError)
                XCTAssertFalse(typedError?.userMessage.contains(sensitiveMarker) ?? true)
                XCTAssertFalse(String(describing: typedError).contains(sensitiveMarker))
            }
        }
    }

    private func authorizationCodeFields(
        verifier: String = GoogleOAuthClientTests.validVerifier,
        redirect: String = "http://127.0.0.1:54321"
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "client_id", value: "desktop-client"),
            URLQueryItem(name: "code", value: "4/0A+realistic=code&shape"),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
        ]
    }
}

@MainActor
private final class QueueHTTPTransport: HTTPTransport {
    struct Response {
        let statusCode: Int
        let data: Data

        static func success(statusCode: Int, body: String) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8))
        }

        static func success(statusCode: Int, data: Data) -> Response {
            Response(statusCode: statusCode, data: data)
        }
    }

    private var responses: [Response]
    private(set) var requestBodies: [String] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestBodies.append(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")
        guard !responses.isEmpty, let url = request.url else {
            throw URLError(.badServerResponse)
        }
        let response = responses.removeFirst()
        return (
            response.data,
            HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
