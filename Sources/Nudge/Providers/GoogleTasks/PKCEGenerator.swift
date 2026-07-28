import CryptoKit
import Foundation
import Security

struct PKCEPair: Equatable, Sendable {
    let verifier: String
    let challenge: String
}

enum PKCEGenerator {
    static func generate() throws -> PKCEPair {
        let verifier = try randomURLSafeString(byteCount: 64)
        return PKCEPair(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func randomState() throws -> String {
        try randomURLSafeString(byteCount: 32)
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw GoogleOAuthError.invalidResponse
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
