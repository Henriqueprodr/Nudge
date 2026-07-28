#if DEBUG
import Foundation
import XCTest
@testable import Nudge

@MainActor
final class ScreenshotDemoTests: XCTestCase {
    func testConfigurationParsesEverySupportedPageAndPNGOutput() throws {
        for page in ScreenshotDemoPage.allCases {
            let output = "/tmp/\(page.outputFilename)"
            let configuration = try ScreenshotDemoConfiguration.parse(
                arguments: [
                    "Nudge",
                    ScreenshotDemoConfiguration.enableArgument,
                    ScreenshotDemoConfiguration.pageArgument,
                    page.rawValue,
                    ScreenshotDemoConfiguration.outputArgument,
                    output,
                ]
            )

            XCTAssertEqual(configuration.page, page)
            XCTAssertEqual(configuration.outputURL.path, output)
            XCTAssertEqual(configuration.outputURL.lastPathComponent, page.outputFilename)
        }
    }

    func testConfigurationRejectsMissingInvalidAndNonPNGValues() {
        XCTAssertThrowsError(
            try ScreenshotDemoConfiguration.parse(
                arguments: ["Nudge", ScreenshotDemoConfiguration.enableArgument]
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenshotDemoConfiguration.ConfigurationError,
                .missingPage
            )
        }

        XCTAssertThrowsError(
            try ScreenshotDemoConfiguration.parse(
                arguments: [
                    "Nudge",
                    ScreenshotDemoConfiguration.enableArgument,
                    ScreenshotDemoConfiguration.pageArgument,
                    "unknown",
                    ScreenshotDemoConfiguration.outputArgument,
                    "/tmp/demo.png",
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenshotDemoConfiguration.ConfigurationError,
                .invalidPage("unknown")
            )
        }

        XCTAssertThrowsError(
            try ScreenshotDemoConfiguration.parse(
                arguments: [
                    "Nudge",
                    ScreenshotDemoConfiguration.enableArgument,
                    ScreenshotDemoConfiguration.pageArgument,
                    ScreenshotDemoPage.account.rawValue,
                    ScreenshotDemoConfiguration.outputArgument,
                    "/tmp/demo.jpg",
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenshotDemoConfiguration.ConfigurationError,
                .invalidOutputExtension
            )
        }
    }

    func testFixturesAreFictionalDeterministicAndSeededInMemory() throws {
        let dependencies = try ScreenshotDemoDependencies()

        XCTAssertEqual(
            try dependencies.repositoryContainer.taskRepository.fetchTaskLists(),
            ScreenshotDemoDependencies.taskListFixtures.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        )
        XCTAssertEqual(
            try dependencies.repositoryContainer.taskRepository.fetchIncompleteTasks().count,
            5
        )
        XCTAssertEqual(
            try dependencies.repositoryContainer.calendarCacheRepository.fetchCalendars(),
            ScreenshotDemoDependencies.calendarFixtures.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        )
        XCTAssertEqual(
            try dependencies.repositoryContainer.taskPanelStateRepository.fetchState()?.selectedTaskListID,
            "demo-today"
        )
        XCTAssertEqual(ScreenshotDemoDependencies.reminderFixture().title, "Design review")
        XCTAssertEqual(Set(SettingsTab.allCases), Set([.account, .reminders, .tasks, .application]))
    }

    func testDemoAdaptersBlockExternalEffects() async throws {
        let dependencies = try ScreenshotDemoDependencies()
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.invalid")))

        do {
            _ = try await dependencies.transport.data(for: request)
            XCTFail("Expected screenshot transport to block the request")
        } catch {
            XCTAssertEqual(dependencies.transport.requestCount, 1)
        }
        XCTAssertFalse(
            dependencies.browserOpener.open(
                try XCTUnwrap(URL(string: "https://example.invalid"))
            )
        )
        XCTAssertEqual(dependencies.browserOpener.openCount, 1)
        XCTAssertEqual(dependencies.launchAtLoginService.mutationCount, 0)
        XCTAssertNil(try dependencies.credentialStore.loadCredential())
        XCTAssertNil(try dependencies.clientSecretStore.loadClientSecret())
        XCTAssertNil(try dependencies.clientConfigurationStore.loadConfiguration())
    }
}
#endif
