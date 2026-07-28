import Foundation
import LocalAuthentication
import Security

@MainActor
final class KeychainGoogleOAuthClientConfigurationStore: GoogleOAuthClientConfigurationStore {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = "com.local.Nudge.google-oauth-configuration",
        account: String = "google-oauth-client-configuration"
    ) {
        self.service = service
        self.account = account
    }

    func loadConfiguration() throws -> GoogleOAuthClientConfiguration? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return nil
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
        do {
            return try decoder.decode(GoogleOAuthClientConfiguration.self, from: data)
        } catch {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
    }

    func saveConfiguration(_ configuration: GoogleOAuthClientConfiguration) throws {
        let data: Data
        do {
            data = try encoder.encode(configuration)
        } catch {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
    }

    func deleteConfiguration() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
