import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nudge", systemImage: "bell.badge") {
            MenuBarContent(
                windowPresentationCoordinator: appDelegate.windowPresentationCoordinator,
                googleTasksSyncCoordinator: appDelegate.googleTasksSyncCoordinator
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
                persistenceStatusMessage: appDelegate.persistenceStatusMessage
            )
        }
    }
}
