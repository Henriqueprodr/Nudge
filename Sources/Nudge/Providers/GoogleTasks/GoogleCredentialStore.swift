import Foundation

@MainActor
protocol GoogleCredentialStore: AnyObject {
    func loadCredential() throws -> GoogleOAuthCredential?
    func loadCredentialAllowingUserInteraction() throws -> GoogleOAuthCredential?
    func saveCredential(_ credential: GoogleOAuthCredential) throws
    func deleteCredential() throws
}

extension GoogleCredentialStore {
    func loadCredentialAllowingUserInteraction() throws -> GoogleOAuthCredential? {
        try loadCredential()
    }
}
