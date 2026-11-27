import Foundation

@MainActor
final class GoogleOAuthClient {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?
        let scope: String?
        let tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
            case tokenType = "token_type"
        }
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let now: @MainActor () -> Date

    init(
        transport: any HTTPTransport,
        decoder: JSONDecoder = JSONDecoder(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.transport = transport
        self.decoder = decoder
        self.now = now
    }

    func exchangeAuthorizationCode(
        _ code: String,
        codeVerifier: String,
        redirectURL: URL,
        configuration: GoogleOAuthConfiguration
    ) async throws -> GoogleOAuthCredential {
        var fields = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
        ]
        if let clientSecret = configuration.clientSecret {
            fields.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        try OAuthTokenRequestValidator.validateAuthorizationCode(fields)
        let response = try await tokenResponse(
            endpoint: configuration.tokenEndpoint,
            fields: fields
        )
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw GoogleOAuthError.offlineCredentialMissing
        }
        return GoogleOAuthCredential(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expirationDate: now().addingTimeInterval(response.expiresIn),
            scope: response.scope ?? configuration.scope,
            tokenType: response.tokenType,
            signedInAt: now()
        )
    }

    func refreshAccessToken(
        credential: GoogleOAuthCredential,
        configuration: GoogleOAuthConfiguration
    ) async throws -> GoogleOAuthCredential {
        var fields = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "refresh_token", value: credential.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        if let clientSecret = configuration.clientSecret {
            fields.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }
        try OAuthTokenRequestValidator.validateRefreshToken(fields)
        let response = try await tokenResponse(
            endpoint: configuration.tokenEndpoint,
            fields: fields
        )
        return GoogleOAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credential.refreshToken,
            expirationDate: now().addingTimeInterval(response.expiresIn),
            scope: response.scope ?? credential.scope,
            tokenType: response.tokenType,
            signedInAt: credential.signedInAt
        )
    }

    private func tokenResponse(
        endpoint: URL,
        fields: [URLQueryItem]
    ) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = OAuthFormEncoder.encode(fields)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw GoogleOAuthError.normalized(error)
        }

        guard response.statusCode == 200 else {
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                let grantType = fields.first { $0.name == "grant_type" }?.value
                if let mappedError = GoogleOAuthErrorMapper.map(
                    error: errorResponse.error,
                    description: errorResponse.errorDescription,
                    grantType: grantType
                ) {
                    throw mappedError
                }
            }
            throw GoogleOAuthError.httpStatus(response.statusCode)
        }

        do {
            let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
            guard
                !tokenResponse.accessToken.isEmpty,
                tokenResponse.expiresIn > 0,
                tokenResponse.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame
            else {
                throw GoogleOAuthError.invalidResponse
            }
            return tokenResponse
        } catch let error as GoogleOAuthError {
            throw error
        } catch {
            throw GoogleOAuthError.decodingFailed
        }
    }
}
