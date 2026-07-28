import Foundation

struct GoogleOAuthCredential: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expirationDate: Date
    var scope: String
    var tokenType: String

    func hasUsableAccessToken(at date: Date, leeway: TimeInterval = 60) -> Bool {
        !accessToken.isEmpty && expirationDate.timeIntervalSince(date) > leeway
    }
}
