import Foundation

@MainActor
protocol GoogleOAuthClientSecretStore: AnyObject {
    func loadClientSecret() throws -> String?
    func loadClientSecretAllowingUserInteraction() throws -> String?
    func hasLegacyClientSecret() throws -> Bool
    func saveClientSecret(_ clientSecret: String) throws
    func deleteClientSecret() throws
}

extension GoogleOAuthClientSecretStore {
    func loadClientSecretAllowingUserInteraction() throws -> String? {
        try loadClientSecret()
    }

    func hasLegacyClientSecret() throws -> Bool {
        false
    }
}
