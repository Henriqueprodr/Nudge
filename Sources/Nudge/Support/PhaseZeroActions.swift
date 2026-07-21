import OSLog

enum PhaseZeroActions {
    private static let logger = Logger(subsystem: "com.local.Nudge", category: "PhaseZero")

    static func showTestReminder() {
        logger.notice("Show Test Reminder selected; implementation begins in Phase 1")
    }

    static func showTaskPanel() {
        logger.notice("Show Task Panel selected; implementation begins in Phase 1")
    }

    static func hideTaskPanel() {
        logger.notice("Hide Task Panel selected; implementation begins in Phase 1")
    }

    static func refreshTasks() {
        logger.notice("Refresh Tasks selected; synchronization begins in a later phase")
    }
}
