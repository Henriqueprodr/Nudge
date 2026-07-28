import Foundation
import XCTest
@testable import Nudge

final class GoogleOAuthClientConfigurationTests: XCTestCase {
    func testConfigurationSourceLabelsStayProviderNeutral() {
        XCTAssertEqual(GoogleOAuthClientConfigurationSource.environment.label, "Build environment")
        XCTAssertEqual(GoogleOAuthClientConfigurationSource.bundled.label, "Included in this build")
        XCTAssertEqual(GoogleOAuthClientConfigurationSource.imported.label, "Imported into Keychain")
    }

    func testDesktopCredentialJSONDecodesAndValidates() throws {
        let configuration = try GoogleOAuthClientConfiguration.decodeDesktopCredential(
            from: desktopCredentialData(clientID: validClientID, clientSecret: "test-secret_123")
        )

        XCTAssertEqual(configuration.clientID, validClientID)
        XCTAssertEqual(configuration.clientSecret, "test-secret_123")
    }

    func testWebCredentialJSONIsRejectedWithoutEchoingValues() {
        let sensitiveMarker = "must-not-appear-in-errors"
        let data = Data(
            """
            {"web":{"client_id":"\(validClientID)","client_secret":"\(sensitiveMarker)"}}
            """.utf8
        )

        XCTAssertThrowsError(
            try GoogleOAuthClientConfiguration.decodeDesktopCredential(from: data)
        ) { error in
            XCTAssertEqual(
                error as? GoogleOAuthClientConfigurationError,
                .notDesktopCredential
            )
            XCTAssertFalse(
                (error as? GoogleOAuthClientConfigurationError)?
                    .userMessage.contains(sensitiveMarker) == true
            )
        }
    }

    func testMalformedAndInvalidDesktopCredentialsAreRejected() {
        XCTAssertThrowsError(
            try GoogleOAuthClientConfiguration.decodeDesktopCredential(
                from: Data("not-json".utf8)
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthClientConfigurationError, .invalidJSON)
        }

        XCTAssertThrowsError(
            try GoogleOAuthClientConfiguration.decodeDesktopCredential(
                from: desktopCredentialData(
                    clientID: "not-a-desktop-client",
                    clientSecret: "test-secret"
                )
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthClientConfigurationError, .invalidClientID)
        }

        XCTAssertThrowsError(
            try GoogleOAuthClientConfiguration.decodeDesktopCredential(
                from: desktopCredentialData(clientID: validClientID, clientSecret: "bad secret")
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthClientConfigurationError, .invalidClientSecret)
        }
    }

    @MainActor
    func testImportedConfigurationPersistsAtomicallyAndCanBeRemoved() throws {
        let store = InMemoryGoogleOAuthClientConfigurationStore()
        let manager = GoogleOAuthClientConfigurationManager(
            store: store,
            environment: [:],
            bundledClientID: nil,
            bundledClientSecret: nil
        )

        try manager.importConfiguration(
            data: desktopCredentialData(clientID: validClientID, clientSecret: "imported-secret")
        )

        XCTAssertEqual(manager.source, .imported)
        XCTAssertEqual(try manager.configuration().clientID, validClientID)
        XCTAssertEqual(try manager.configuration().clientSecret, "imported-secret")
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.configuration, manager.importedConfiguration)

        try manager.removeImportedConfiguration()

        XCTAssertNil(manager.source)
        XCTAssertNil(manager.importedConfiguration)
        XCTAssertEqual(store.deleteCount, 1)
    }

    @MainActor
    func testConfigurationPrecedenceIsEnvironmentThenBundleThenImport() throws {
        let imported = try GoogleOAuthClientConfiguration(
            clientID: clientID(prefix: "imported"),
            clientSecret: "imported-secret"
        )
        let store = InMemoryGoogleOAuthClientConfigurationStore(configuration: imported)
        let environmentManager = GoogleOAuthClientConfigurationManager(
            store: store,
            environment: [
                "GOOGLE_OAUTH_CLIENT_ID": clientID(prefix: "environment"),
                "GOOGLE_OAUTH_CLIENT_SECRET": "environment-secret",
            ],
            bundledClientID: clientID(prefix: "bundled"),
            bundledClientSecret: "bundled-secret"
        )
        XCTAssertEqual(environmentManager.source, .environment)
        XCTAssertEqual(
            try environmentManager.configuration().clientID,
            clientID(prefix: "environment")
        )

        let bundledManager = GoogleOAuthClientConfigurationManager(
            store: store,
            environment: [:],
            bundledClientID: clientID(prefix: "bundled"),
            bundledClientSecret: "bundled-secret"
        )
        XCTAssertEqual(bundledManager.source, .bundled)
        XCTAssertEqual(
            try bundledManager.configuration().clientID,
            clientID(prefix: "bundled")
        )

        let importedManager = GoogleOAuthClientConfigurationManager(
            store: store,
            environment: [:],
            bundledClientID: nil,
            bundledClientSecret: nil
        )
        XCTAssertEqual(importedManager.source, .imported)
        XCTAssertEqual(try importedManager.configuration().clientID, imported.clientID)
    }

    func testConfigurationCanChangeOnlyWhileSignedOutAndIdle() {
        XCTAssertTrue(
            GoogleOAuthClientConfigurationChangePolicy.canModify(
                isTasksAuthenticated: false,
                hasStoredGoogleCredential: false,
                providerOperationInProgress: false
            )
        )
        XCTAssertFalse(
            GoogleOAuthClientConfigurationChangePolicy.canModify(
                isTasksAuthenticated: true,
                hasStoredGoogleCredential: false,
                providerOperationInProgress: false
            )
        )
        XCTAssertFalse(
            GoogleOAuthClientConfigurationChangePolicy.canModify(
                isTasksAuthenticated: false,
                hasStoredGoogleCredential: true,
                providerOperationInProgress: false
            )
        )
        XCTAssertFalse(
            GoogleOAuthClientConfigurationChangePolicy.canModify(
                isTasksAuthenticated: false,
                hasStoredGoogleCredential: false,
                providerOperationInProgress: true
            )
        )
    }

    private var validClientID: String {
        clientID(prefix: "test-client")
    }

    private func clientID(prefix: String) -> String {
        [prefix, "apps", "googleusercontent", "com"].joined(separator: ".")
    }

    private func desktopCredentialData(clientID: String, clientSecret: String) -> Data {
        Data(
            """
            {"installed":{"client_id":"\(clientID)","client_secret":"\(clientSecret)"}}
            """.utf8
        )
    }
}

@MainActor
private final class InMemoryGoogleOAuthClientConfigurationStore:
    GoogleOAuthClientConfigurationStore {
    var configuration: GoogleOAuthClientConfiguration?
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(configuration: GoogleOAuthClientConfiguration? = nil) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> GoogleOAuthClientConfiguration? {
        configuration
    }

    func saveConfiguration(_ configuration: GoogleOAuthClientConfiguration) throws {
        saveCount += 1
        self.configuration = configuration
    }

    func deleteConfiguration() throws {
        deleteCount += 1
        configuration = nil
    }
}
