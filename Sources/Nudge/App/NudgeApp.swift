import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nudge", image: "MenuBarIcon") {
            MenuBarContent(
                windowPresentationCoordinator: appDelegate.windowPresentationCoordinator,
                googleTasksSyncCoordinator: appDelegate.googleTasksSyncCoordinator,
                mascotController: appDelegate.mascotController
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                calendarCoordinator: appDelegate.calendarScheduleCoordinator,
                googleTasksCoordinator: appDelegate.googleTasksSyncCoordinator,
                googleOAuthConfigurationManager: appDelegate.googleOAuthClientConfigurationManager,
                windowCoordinator: appDelegate.windowPresentationCoordinator,
                launchAtLoginManager: appDelegate.launchAtLoginManager,
                persistenceStatusMessage: appDelegate.persistenceStatusMessage,
                taskNagCoordinator: appDelegate.taskNagCoordinator,
                mascotController: appDelegate.mascotController
            )
        }
    }
}
