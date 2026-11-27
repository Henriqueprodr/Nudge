import Foundation
import Observation

enum GoogleOAuthClientConfigurationSource: Equatable, Sendable {
    case environment
    case bundled
    case imported

    var label: String {
        switch self {
        case .environment:
            return "Build environment"
        case .bundled:
            return "Built into Nudge"
        case .imported:
            return "Imported into Keychain"
        }
    }
}

@MainActor
@Observable
final class GoogleOAuthClientConfigurationManager {
    private let store: any GoogleOAuthClientConfigurationStore
    private let environment: [String: String]
    private let bundledClientID: String?
    private let bundledClientSecret: String?
    private(set) var importedConfiguration: GoogleOAuthClientConfiguration?
    private(set) var secureStoreStatusMessage: String?

    init(
        store: any GoogleOAuthClientConfigurationStore,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledClientID: String? = Bundle.main.object(
            forInfoDictionaryKey: "GoogleOAuthClientID"
        ) as? String ?? Bundle.main.object(forInfoDictionaryKey: "GoogleTasksClientID") as? String,
        bundledClientSecret: String? = Bundle.main.object(
            forInfoDictionaryKey: "GoogleOAuthClientSecret"
        ) as? String
    ) {
        self.store = store
        self.environment = environment
        self.bundledClientID = bundledClientID
        self.bundledClientSecret = bundledClientSecret
        do {
            importedConfiguration = try store.loadConfiguration()
        } catch {
            importedConfiguration = nil
            secureStoreStatusMessage = GoogleOAuthClientConfigurationError.secureStoreFailed.userMessage
        }
    }

    var source: GoogleOAuthClientConfigurationSource? {
        try? resolvedConfiguration().source
    }

    var hasImportedConfiguration: Bool {
        importedConfiguration != nil
    }

    func configuration() throws -> GoogleOAuthConfiguration {
        try resolvedConfiguration().configuration
    }

    func importConfiguration(from url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw GoogleOAuthClientConfigurationError.unreadableFile
        }
        try importConfiguration(data: data)
    }

    func importConfiguration(data: Data) throws {
        let configuration = try GoogleOAuthClientConfiguration.decodeDesktopCredential(from: data)
        do {
            try store.saveConfiguration(configuration)
        } catch {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
        importedConfiguration = configuration
        secureStoreStatusMessage = nil
    }

    func removeImportedConfiguration() throws {
        do {
            try store.deleteConfiguration()
        } catch {
            throw GoogleOAuthClientConfigurationError.secureStoreFailed
        }
        importedConfiguration = nil
        secureStoreStatusMessage = nil
    }

    private func resolvedConfiguration() throws -> (
        configuration: GoogleOAuthConfiguration,
        source: GoogleOAuthClientConfigurationSource
    ) {
        let environmentClientID = usable(
            environment["GOOGLE_OAUTH_CLIENT_ID"] ?? environment["GOOGLE_TASKS_CLIENT_ID"]
        )
        if let environmentClientID {
            let clientSecret = usable(
                environment["GOOGLE_OAUTH_CLIENT_SECRET"]
                    ?? environment["GOOGLE_TASKS_CLIENT_SECRET"]
            )
            return (
                try validatedConfiguration(clientID: environmentClientID, clientSecret: clientSecret),
                .environment
            )
        }

        // A client the user imported is an explicit choice, and their stored Google credential
        // belongs to it, so it wins over the client built into this release.
        if let importedConfiguration {
            return (
                GoogleOAuthConfiguration(
                    clientID: importedConfiguration.clientID,
                    clientSecret: importedConfiguration.clientSecret
                ),
                .imported
            )
        }

        if let bundledClientID = usable(bundledClientID) {
            return (
                try validatedConfiguration(
                    clientID: bundledClientID,
                    clientSecret: usable(bundledClientSecret)
                ),
                .bundled
            )
        }
        throw GoogleOAuthError.configurationMissing
    }

    private func validatedConfiguration(
        clientID: String,
        clientSecret: String?
    ) throws -> GoogleOAuthConfiguration {
        guard GoogleOAuthClientConfiguration.isValidClientID(clientID) else {
            throw GoogleOAuthClientConfigurationError.invalidClientID
        }
        if let clientSecret,
           !GoogleOAuthClientConfiguration.isValidClientSecret(clientSecret) {
            throw GoogleOAuthClientConfigurationError.invalidClientSecret
        }
        return GoogleOAuthConfiguration(clientID: clientID, clientSecret: clientSecret)
    }

    private func usable(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.contains("$(") else { return nil }
        return normalized
    }
}
