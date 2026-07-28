import Foundation

struct GoogleOAuthClientConfiguration: Codable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String

    init(clientID: String, clientSecret: String) throws {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidClientID(normalizedClientID) else {
            throw GoogleOAuthClientConfigurationError.invalidClientID
        }
        guard Self.isValidClientSecret(normalizedClientSecret) else {
            throw GoogleOAuthClientConfigurationError.invalidClientSecret
        }
        self.clientID = normalizedClientID
        self.clientSecret = normalizedClientSecret
    }

    static func decodeDesktopCredential(from data: Data) throws -> Self {
        let credentialFile: DesktopCredentialFile
        do {
            credentialFile = try JSONDecoder().decode(DesktopCredentialFile.self, from: data)
        } catch let error as DecodingError {
            if case .keyNotFound = error {
                throw GoogleOAuthClientConfigurationError.notDesktopCredential
            }
            throw GoogleOAuthClientConfigurationError.invalidJSON
        } catch {
            throw GoogleOAuthClientConfigurationError.invalidJSON
        }
        return try Self(
            clientID: credentialFile.installed.clientID,
            clientSecret: credentialFile.installed.clientSecret
        )
    }

    static func isValidClientID(_ clientID: String) -> Bool {
        clientID.range(
            of: #"^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$"#,
            options: .regularExpression
        ) != nil
    }

    static func isValidClientSecret(_ clientSecret: String) -> Bool {
        clientSecret.range(
            of: #"^[A-Za-z0-9._~-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private struct DesktopCredentialFile: Decodable {
        let installed: InstalledCredential
    }

    private struct InstalledCredential: Decodable {
        let clientID: String
        let clientSecret: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
        }
    }
}

enum GoogleOAuthClientConfigurationError: Error, Equatable, Sendable {
    case invalidJSON
    case notDesktopCredential
    case invalidClientID
    case invalidClientSecret
    case unreadableFile
    case secureStoreFailed

    var userMessage: String {
        switch self {
        case .invalidJSON:
            return "The selected file is not valid JSON."
        case .notDesktopCredential:
            return "Select an OAuth client JSON created for a Google Desktop app."
        case .invalidClientID:
            return "The Desktop OAuth client ID is invalid."
        case .invalidClientSecret:
            return "The Desktop OAuth client secret is invalid."
        case .unreadableFile:
            return "The selected OAuth file could not be read."
        case .secureStoreFailed:
            return "The OAuth client configuration could not be stored securely."
        }
    }
}
