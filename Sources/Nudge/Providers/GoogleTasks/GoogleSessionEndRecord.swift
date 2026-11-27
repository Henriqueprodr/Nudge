import Foundation

/// Why and when Google last ended Nudge's offline session.
///
/// Google returns `invalid_grant` when a refresh token stops working. The most common cause for
/// a personal Desktop OAuth client is the Cloud project's "Testing" publishing status, which
/// expires refresh tokens seven days after consent. Recording the sign-in date lets Nudge say
/// so instead of showing a generic signed-out state.
struct GoogleSessionEndRecord: Codable, Equatable, Sendable {
    static let testingModeLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let testingModeTolerance: TimeInterval = 18 * 60 * 60

    let endedAt: Date
    let signedInAt: Date?

    var sessionLifetime: TimeInterval? {
        signedInAt.map { endedAt.timeIntervalSince($0) }
    }

    /// `true` when the session lasted about seven days, Google's Testing-mode token lifetime.
    var matchesTestingModeExpiry: Bool {
        guard let sessionLifetime else { return false }
        return abs(sessionLifetime - Self.testingModeLifetime) <= Self.testingModeTolerance
    }

    /// - Parameter usesOwnOAuthClient: `true` when the user brought their own Google Cloud
    ///   OAuth client, so the Testing-mode advice is theirs to act on. Users of the client built
    ///   into Nudge cannot change its publishing status, so they only get the plain explanation.
    func explanation(
        usesOwnOAuthClient: Bool = true,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        if usesOwnOAuthClient, matchesTestingModeExpiry {
            return "Google ended this session exactly a week after sign-in. Your Google Cloud "
                + "OAuth app is probably still in Testing mode; publish it to production so "
                + "sign-in lasts."
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Google ended Nudge's session on \(formatter.string(from: endedAt)). "
            + "Sign in again to resume Calendar and Tasks."
    }
}
