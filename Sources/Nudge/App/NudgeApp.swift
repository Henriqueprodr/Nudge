import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Nudge", systemImage: "bell.badge") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsPlaceholderView()
        }
    }
}
