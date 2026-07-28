import Foundation
import LocalAuthentication
import Security

@MainActor
final class KeychainGoogleOAuthClientSecretStore: GoogleOAuthClientSecretStore {
    private let service: String
    private let account: String
    private let legacyAccount: String
    private var activeAccount: String
    private(set) var compatibilityMigrationFailed = false

    init(
        service: String = "com.local.Nudge.google-oauth-configuration",
        account: String = "google-oauth-client-secret",
        legacyAccount: String = "google-tasks-client-secret"
    ) {
        self.service = service
        self.account = account
        self.legacyAccount = legacyAccount
        activeAccount = account
    }

    func loadClientSecret() throws -> String? {
        try loadClientSecret(allowingUserInteraction: false)
    }

    func loadClientSecretAllowingUserInteraction() throws -> String? {
        try loadClientSecret(allowingUserInteraction: true)
    }

    func hasLegacyClientSecret() throws -> Bool {
        // Existence checks do not request the protected value and therefore must
        // never present a Keychain authorization dialog during launch.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        var query = keychainQuery(account: legacyAccount)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            return false
        }
        throw GoogleOAuthError.credentialStoreFailed
    }

    private func loadClientSecret(
        allowingUserInteraction: Bool
    ) throws -> String? {
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
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let clientSecret = String(data: data, encoding: .utf8),
            !clientSecret.isEmpty
        else {
            throw GoogleOAuthError.credentialStoreFailed
        }
        return clientSecret
    }

    func saveClientSecret(_ clientSecret: String) throws {
        guard !clientSecret.isEmpty else {
            throw GoogleOAuthError.configurationMissing
        }
        let data = Data(clientSecret.utf8)
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

    private func applyAuthenticationPolicy(
        allowingUserInteraction: Bool,
        to query: inout [String: Any]
    ) {
        guard !allowingUserInteraction else { return }
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
    }

    func deleteClientSecret() throws {
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

        // Keep the legacy item as a recovery fallback. Deleting it is a separate
        // protected Keychain operation that can display another authorization
        // prompt. Normal reads prefer the new provider-neutral item and never
        // consult the fallback once this copy succeeds.
        return true
    }
}
