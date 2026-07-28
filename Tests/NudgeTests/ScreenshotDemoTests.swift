#if DEBUG
import AppKit
import Foundation
import XCTest
@testable import Nudge

@MainActor
final class ScreenshotDemoTests: XCTestCase {
    private struct DeniedCapturePermission: ScreenshotCapturePermissionChecking {
        func requirePermission() throws {
            throw ScreenshotDemoCaptureController.CaptureError.permissionRequired
        }
    }

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
        XCTAssertEqual(
            try XCTUnwrap(
                dependencies.repositoryContainer.syncMetadataRepository.fetchMetadata()
            ).lastSuccessfulRefreshAt,
            ScreenshotDemoDependencies.referenceDate
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

    func testNativeMenuMatchesProductionActionsAndMacConventions() {
        let menu = ScreenshotDemoNativeMenu.makeMenu(target: ScreenshotDemoMenuTarget())
        let actionItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(
            actionItems.map(\.title),
            [
                AppMenuAction.showTestReminder.rawValue,
                AppMenuAction.showTaskPanel.rawValue,
                AppMenuAction.hideTaskPanel.rawValue,
                AppMenuLabel.taskPanelCorner,
                AppMenuAction.resetTaskPanelPosition.rawValue,
                AppMenuLabel.allowReminderOverFullScreenApps,
                AppMenuLabel.allowTaskPanelOverFullScreenApps,
                AppMenuAction.refreshTasks.rawValue,
                "Settings…",
                AppMenuAction.quit.rawValue,
            ]
        )
        XCTAssertEqual(actionItems.map(\.title), ScreenshotDemoNativeMenu.orderedTitles)
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertTrue(actionItems.allSatisfy(\.isEnabled))
        XCTAssertEqual(menu.items.filter(\.isSeparatorItem).count, 2)

        let cornerItem = actionItems[3]
        XCTAssertEqual(cornerItem.submenu?.items.map(\.title), ScreenCorner.allCases.map(\.rawValue))
        XCTAssertEqual(
            cornerItem.submenu?.items.map(\.state),
            ScreenCorner.allCases.map { _ in .off }
        )
        XCTAssertEqual(actionItems[5].state, .off)
        XCTAssertEqual(actionItems[6].state, .off)
        XCTAssertEqual(actionItems[8].keyEquivalent, ",")
        XCTAssertEqual(actionItems[8].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(actionItems[9].keyEquivalent, "q")
        XCTAssertEqual(actionItems[9].keyEquivalentModifierMask, [.command])
    }

    func testCapturePermissionDenialIsExplicitAndValueFree() {
        let checker = DeniedCapturePermission()

        XCTAssertThrowsError(try checker.requirePermission()) { error in
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "Screen Recording permission is required. Enable Nudge in System Settings → "
                    + "Privacy & Security → Screen & System Audio Recording, then run the "
                    + "capture script again."
            )
        }
    }

    func testNativeWindowStylesKeepOnlySettingsTitled() {
        let settings = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let reminder = ReminderOverlayWindow(contentRect: .zero)
        let taskPanel = TaskPanelWindow(contentRect: .zero)

        XCTAssertTrue(settings.styleMask.contains(.titled))
        XCTAssertNotNil(settings.standardWindowButton(.closeButton))
        XCTAssertNotNil(settings.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(settings.standardWindowButton(.zoomButton))
        XCTAssertFalse(reminder.styleMask.contains(.titled))
        XCTAssertFalse(taskPanel.styleMask.contains(.titled))
        XCTAssertTrue(reminder.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(taskPanel.styleMask.contains(.nonactivatingPanel))
    }
}
#endif
