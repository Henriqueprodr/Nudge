import Foundation
import LocalAuthentication
import Security

@MainActor
final class KeychainGoogleCredentialStore: GoogleCredentialStore {
    private let service: String
    private let account: String
    private let legacyAccount: String
    private var activeAccount: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var compatibilityMigrationFailed = false

    init(
        service: String = "com.local.Nudge.google-oauth",
        account: String = "google-account",
        legacyAccount: String = "google-tasks"
    ) {
        self.service = service
        self.account = account
        self.legacyAccount = legacyAccount
        activeAccount = account
    }

    func loadCredential() throws -> GoogleOAuthCredential? {
        try loadCredential(allowingUserInteraction: false)
    }

    func loadCredentialAllowingUserInteraction() throws -> GoogleOAuthCredential? {
        try loadCredential(allowingUserInteraction: true)
    }

    private func loadCredential(
        allowingUserInteraction: Bool
    ) throws -> GoogleOAuthCredential? {
        // A hosted XCTest process must never inspect the user's real Keychain.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        applyAuthenticationPolicy(
            allowingUserInteraction: allowingUserInteraction,
            to: &query
        )

        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            guard allowingUserInteraction else { return nil }
            var legacyQuery = keychainQuery(account: legacyAccount)
            legacyQuery[kSecReturnData as String] = true
            legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            applyAuthenticationPolicy(
                allowingUserInteraction: allowingUserInteraction,
                to: &legacyQuery
            )
            status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                if migrateLegacyItem(data: data) {
                    activeAccount = account
                } else {
                    compatibilityMigrationFailed = true
                    activeAccount = legacyAccount
                }
            }
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GoogleOAuthError.credentialStoreFailed
        }
        do {
            return try decoder.decode(GoogleOAuthCredential.self, from: data)
        } catch {
            throw GoogleOAuthError.credentialStoreFailed
        }
    }

    private func applyAuthenticationPolicy(
        allowingUserInteraction: Bool,
        to query: inout [String: Any]
    ) {
        guard !allowingUserInteraction else { return }
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
    }

    func saveCredential(_ credential: GoogleOAuthCredential) throws {
        let data: Data
        do {
            data = try encoder.encode(credential)
        } catch {
            throw GoogleOAuthError.credentialStoreFailed
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw GoogleOAuthError.credentialStoreFailed
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw GoogleOAuthError.credentialStoreFailed
        }
    }

    func deleteCredential() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleOAuthError.credentialStoreFailed
        }
    }

    private var baseQuery: [String: Any] {
        keychainQuery(account: activeAccount)
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func migrateLegacyItem(data: Data) -> Bool {
        var attributes = keychainQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        let writeStatus: OSStatus
        if addStatus == errSecDuplicateItem {
            writeStatus = SecItemUpdate(
                keychainQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
        } else {
            writeStatus = addStatus
        }
        guard writeStatus == errSecSuccess else {
            return false
        }

        let deleteStatus = SecItemDelete(keychainQuery(account: legacyAccount) as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            compatibilityMigrationFailed = true
        }
        return true
    }
}
