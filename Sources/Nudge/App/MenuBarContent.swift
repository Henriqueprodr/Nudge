import AppKit
import SwiftUI

struct MenuBarContent: View {
    let windowPresentationCoordinator: WindowPresentationCoordinator
    let googleTasksSyncCoordinator: GoogleTasksSyncCoordinator
    var mascotController: MascotController?

    var body: some View {
        Button(AppMenuAction.showTestReminder.rawValue) {
            windowPresentationCoordinator.showTestReminder()
        }

        Button(AppMenuAction.showTestTaskNag.rawValue) {
            windowPresentationCoordinator.showTestTaskNag()
        }

        if let mascotController, mascotController.settings.isEnabled {
            Button(AppMenuAction.summonBird.rawValue) {
                mascotController.summon()
            }
        }

        Divider()

        Button(AppMenuAction.showTaskPanel.rawValue) {
            windowPresentationCoordinator.showTaskPanel()
        }

        Button(AppMenuAction.hideTaskPanel.rawValue) {
            windowPresentationCoordinator.hideTaskPanel()
        }

        Menu(AppMenuLabel.taskPanelCorner) {
            ForEach(ScreenCorner.allCases, id: \.self) { corner in
                Button(corner.rawValue) {
                    windowPresentationCoordinator.setTaskPanelCorner(corner)
                }
            }
        }

        Button(AppMenuAction.resetTaskPanelPosition.rawValue) {
            windowPresentationCoordinator.resetTaskPanelPosition()
        }

        Toggle(
            AppMenuLabel.allowReminderOverFullScreenApps,
            isOn: Binding(
                get: {
                    windowPresentationCoordinator.reminderOverFullScreen
                },
                set: { isAllowed in
                    windowPresentationCoordinator.setReminderOverFullScreen(isAllowed)
                }
            )
        )

        Toggle(
            AppMenuLabel.allowTaskPanelOverFullScreenApps,
            isOn: Binding(
                get: { windowPresentationCoordinator.taskPanelOverFullScreen },
                set: { windowPresentationCoordinator.setTaskPanelOverFullScreen($0) }
            )
        )

        Button(AppMenuAction.refreshTasks.rawValue) {
            googleTasksSyncCoordinator.requestRefresh(.manual)
        }
        .disabled(googleTasksSyncCoordinator.isRefreshing)

        if let mascotController, mascotController.settings.isEnabled {
            Divider()

            if mascotController.isMuted {
                Button(AppMenuAction.unmuteBird.rawValue) {
                    mascotController.clearDoNotDisturb()
                }
            } else {
                Button(AppMenuAction.muteBird.rawValue) {
                    mascotController.muteForOneHour()
                }
            }
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
