import Foundation

struct GoogleOAuthCredential: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expirationDate: Date
    var scope: String
    var tokenType: String
    /// When the user completed the interactive sign-in that produced this refresh token.
    /// `nil` for credentials stored before sign-in dates were recorded.
    var signedInAt: Date? = nil

    func hasUsableAccessToken(at date: Date, leeway: TimeInterval = 60) -> Bool {
        !accessToken.isEmpty && expirationDate.timeIntervalSince(date) > leeway
    }
}
