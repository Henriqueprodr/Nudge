import AppKit
import SwiftUI

struct MenuBarContent: View {
    var body: some View {
        Button(AppMenuAction.showTestReminder.rawValue) {
            PhaseZeroActions.showTestReminder()
        }

        Divider()

        Button(AppMenuAction.showTaskPanel.rawValue) {
            PhaseZeroActions.showTaskPanel()
        }

        Button(AppMenuAction.hideTaskPanel.rawValue) {
            PhaseZeroActions.hideTaskPanel()
        }

        Button(AppMenuAction.refreshTasks.rawValue) {
            PhaseZeroActions.refreshTasks()
        }

        Divider()

        SettingsLink {
            Text(AppMenuAction.settings.rawValue)
        }

        Button(AppMenuAction.quit.rawValue) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
