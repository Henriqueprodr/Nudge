import Foundation
import Observation

/// Feeds smart task nags into the reminder overlay.
///
/// It recomputes from the local Tasks cache only: after each Tasks sync or task action, after
/// wake, after settings changes, and after each nag is shown, snoozed, or silenced. It never
/// calls Google APIs itself.
@MainActor
@Observable
final class TaskNagCoordinator {
    typealias ReminderSink = @MainActor ([Reminder]) throws -> Void

    private let taskRepository: any TaskRepository
    private let historyRepository: any TaskNagHistoryRepository
    private let settingsRepository: any TaskNagSettingsRepository
    @ObservationIgnored private let reminderSink: ReminderSink
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private var history: TaskNagHistory

    private(set) var settings: TaskNagSettings
    /// When the next nag is due, for Settings and the menu.
    private(set) var nextNagDate: Date?
    private(set) var outstandingTaskCount = 0

    init(
        taskRepository: any TaskRepository,
        historyRepository: any TaskNagHistoryRepository,
        settingsRepository: any TaskNagSettingsRepository,
        reminderSink: @escaping ReminderSink,
        now: @escaping @MainActor () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.taskRepository = taskRepository
        self.historyRepository = historyRepository
        self.settingsRepository = settingsRepository
        self.reminderSink = reminderSink
        self.now = now
        self.calendar = calendar
        history = historyRepository.fetchHistory()
        settings = (settingsRepository.fetchSettings() ?? .defaultValue).validated
    }

    func updateSettings(_ newSettings: TaskNagSettings) {
        settings = newSettings.validated
        settingsRepository.save(settings)
        recompute()
    }

    /// Rebuilds the next nag from the cache.
    func recompute() {
        let currentDate = now()
        let tasks = (try? taskRepository.fetchIncompleteTasks()) ?? []
        history.reconcile(withIncompleteTaskIDs: Set(tasks.map(\.id)), now: currentDate)
        if let cutoff = calendar.date(byAdding: .day, value: -3, to: currentDate) {
            history.pruneDeliveries(before: cutoff)
        }
        historyRepository.save(history)

        let policy = TaskNagPolicy(settings: settings, calendar: calendar)
        outstandingTaskCount = policy.candidates(tasks: tasks, history: history, now: currentDate)
            .count
        let reminder = policy.nextReminder(tasks: tasks, history: history, now: currentDate)
        nextNagDate = reminder?.triggerDate
        try? reminderSink(reminder.map { [$0] } ?? [])
    }

    /// Whether `date` falls inside the configured quiet hours (shared with the mascot).
    func isInQuietHours(_ date: Date) -> Bool {
        TaskNagPolicy(settings: settings, calendar: calendar).isInQuietHours(date)
    }

    /// Records that a nag reached the screen, which paces the next one.
    func reminderWasPresented(_ reminder: Reminder) {
        guard let context = reminder.taskContext else { return }
        history.recordDelivery(of: context.taskIDs, at: now())
        historyRepository.save(history)
        recompute()
    }

    func reminderWasSnoozed(_ reminder: Reminder, until date: Date) {
        guard let context = reminder.taskContext else { return }
        history.snooze(context.taskIDs, until: date)
        historyRepository.save(history)
        recompute()
    }

    /// "Not today": silence every task in the nag until quiet hours end tomorrow.
    func silenceUntilTomorrow(_ reminder: Reminder) {
        guard let context = reminder.taskContext else { return }
        let currentDate = now()
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: currentDate)
        ) ?? currentDate.addingTimeInterval(24 * 3600)
        let resumeAt = calendar.date(
            bySettingHour: settings.quietHoursEndHour, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
        history.silence(context.taskIDs, until: resumeAt)
        historyRepository.save(history)
        recompute()
    }
}
