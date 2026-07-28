enum AppMenuAction: String, CaseIterable {
    case showTestReminder = "Show Test Reminder"
    case showTaskPanel = "Show Task Panel"
    case hideTaskPanel = "Hide Task Panel"
    case resetTaskPanelPosition = "Reset Task Panel Position"
    case refreshTasks = "Refresh Tasks"
    case settings = "Settings"
    case quit = "Quit"
}

enum AppMenuLabel {
    static let taskPanelCorner = "Task Panel Corner"
    static let allowReminderOverFullScreenApps =
        "Allow Reminder Over Full-Screen Apps"
    static let allowTaskPanelOverFullScreenApps =
        "Allow Task Panel Over Full-Screen Apps"
}
