import Foundation

@MainActor
final class ReminderPresentationCoordinator {
    private let scheduler: ReminderScheduler
    private let windowController: ReminderOverlayWindowController
    private let wakeTimer: ReminderWakeTimer
    private let sourceOpener: any ReminderSourceOpening
    private let notificationFallback: any ReminderNotificationFallbackProviding
    private let soundPlayer: any ReminderSoundPlaying
    private let now: @MainActor () -> Date
    private var pendingReminders: [Reminder] = []
    private var knownReminders: [ReminderOccurrenceID: Reminder] = [:]
    private var deliveredThisLaunch: Set<ReminderOccurrenceID> = []
    private var fallbackInFlight: Set<ReminderOccurrenceID> = []
    private var isSessionActive = true
    var reminderSound = ReminderSound.defaultValue
    /// Routes `ReminderAction`s to the app layer. Returns `true` on success.
    var actionHandler: (@MainActor (ReminderAction, Reminder) async -> Bool)?
    /// Observes each reminder that actually reached the screen (used by task nags).
    var onReminderPresented: (@MainActor (Reminder) -> Void)?
    /// Observes successful snoozes so task nags can pace themselves.
    var onReminderSnoozed: (@MainActor (Reminder, Date) -> Void)?

    var nextScheduledPresentationDate: Date? {
        wakeTimer.scheduledDate
    }

    init(
        scheduler: ReminderScheduler,
        windowController: ReminderOverlayWindowController,
        wakeTimer: ReminderWakeTimer = ReminderWakeTimer(),
        sourceOpener: any ReminderSourceOpening = ReminderSourceOpener(),
        notificationFallback: any ReminderNotificationFallbackProviding = ReminderNotificationFallback(),
        soundPlayer: any ReminderSoundPlaying = SystemReminderSoundPlayer(),
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.windowController = windowController
        self.wakeTimer = wakeTimer
        self.sourceOpener = sourceOpener
        self.notificationFallback = notificationFallback
        self.soundPlayer = soundPlayer
        self.now = now
    }

    func process(_ reminders: [Reminder]) throws {
        for reminder in reminders {
            knownReminders[reminder.occurrenceID] = reminder
        }
        let evaluations = try scheduler.rebuildSchedule(from: Array(knownReminders.values))
        apply(evaluations)
    }

    func replaceCalendarReminders(with reminders: [Reminder]) throws {
        try replaceReminders(ofKind: .calendar, with: reminders)
    }

    /// Replaces every task nag without touching calendar or local reminders.
    func replaceTaskReminders(with reminders: [Reminder]) throws {
        try replaceReminders(ofKind: .task, with: reminders)
    }

    private func replaceReminders(
        ofKind sourceKind: ReminderOccurrenceID.SourceKind,
        with reminders: [Reminder]
    ) throws {
        knownReminders = knownReminders.filter { occurrenceID, _ in
            occurrenceID.sourceKind != sourceKind
        }
        pendingReminders.removeAll { reminder in
            reminder.occurrenceID.sourceKind == sourceKind
        }
        try process(reminders.filter { $0.occurrenceID.sourceKind == sourceKind })
    }

    /// Runs a source-specific action for the reminder on screen. The handler returns `true` when
    /// the action succeeded; the reminder is then recorded as acted on and dismissed.
    func performCurrentReminderAction(_ action: ReminderAction) {
        guard let reminder = windowController.presentedReminder,
              reminder.actions.contains(action) else {
            return
        }
        guard let actionHandler else {
            windowController.endAction(errorMessage: "This action is unavailable right now.")
            return
        }
        windowController.beginAction()
        Task { @MainActor [weak self] in
            let succeeded = await actionHandler(action, reminder)
            guard let self,
                  self.windowController.presentedReminder?.occurrenceID == reminder.occurrenceID
            else { return }
            guard succeeded else {
                self.windowController.endAction(errorMessage: "That didn't work. Try again.")
                return
            }
            try? self.scheduler.markActed(reminder.occurrenceID)
            self.windowController.dismiss()
            self.presentNextIfNeeded()
        }
    }

    func dismissCurrentReminder() {
        guard let reminder = windowController.presentedReminder else {
            return
        }
        try? scheduler.dismiss(reminder.occurrenceID)
        windowController.dismiss()
        presentNextIfNeeded()
    }

    static let calendarSnoozeInterval: TimeInterval = 10 * 60
    static let taskSnoozeInterval: TimeInterval = 60 * 60

    func snoozeCurrentReminder(for requestedInterval: TimeInterval? = nil) {
        guard let reminder = windowController.presentedReminder else {
            return
        }
        let interval = requestedInterval ?? (
            reminder.occurrenceID.sourceKind == .task
                ? Self.taskSnoozeInterval
                : Self.calendarSnoozeInterval
        )
        windowController.beginAction()
        do {
            let snoozedUntil = now().addingTimeInterval(interval)
            try scheduler.snooze(reminder.occurrenceID, until: snoozedUntil)
            deliveredThisLaunch.remove(reminder.occurrenceID)
            pendingReminders.removeAll { $0.occurrenceID == reminder.occurrenceID }
            windowController.dismiss()
            let evaluations = try scheduler.rebuildSchedule(from: Array(knownReminders.values))
            apply(evaluations)
            onReminderSnoozed?(reminder, snoozedUntil)
        } catch {
            windowController.endAction(errorMessage: "This reminder could not be snoozed.")
        }
    }

    func openCurrentReminderSource() {
        guard let reminder = windowController.presentedReminder else {
            return
        }
        windowController.beginAction()
        guard sourceOpener.openSource(for: reminder) else {
            windowController.endAction(errorMessage: "The source item could not be opened.")
            return
        }
        do {
            try scheduler.markActed(reminder.occurrenceID)
            windowController.dismiss()
            presentNextIfNeeded()
        } catch {
            windowController.endAction(errorMessage: "The reminder action could not be saved.")
        }
    }

    func prepareForSleep() {
        isSessionActive = false
        wakeTimer.cancel()
    }

    func setSessionActive(_ isActive: Bool, recoverIfActivated: Bool = true) {
        isSessionActive = isActive
        if isActive, recoverIfActivated {
            recoverAfterLifecycleChange()
        }
    }

    func recoverAfterLifecycleChange() {
        do {
            let evaluations = try scheduler.rebuildSchedule(from: Array(knownReminders.values))
            apply(evaluations)
        } catch {
            wakeTimer.cancel()
        }
    }

    func previewReminderSound() {
        soundPlayer.play(reminderSound)
    }

    func stopReminderSound() {
        soundPlayer.stop()
    }

    func setNotificationFallbackSoundEnabled(_ isEnabled: Bool) {
        notificationFallback.setSoundEnabled(isEnabled)
    }

    private func apply(_ evaluations: [ReminderScheduler.Evaluation]) {
        let terminalIDs = Set(evaluations.compactMap { evaluation -> ReminderOccurrenceID? in
            switch evaluation {
            case let .expired(identifier), let .ignored(identifier):
                return identifier
            default:
                return nil
            }
        })
        pendingReminders.removeAll { terminalIDs.contains($0.occurrenceID) }

        let presentedIDs = windowController.presentedReminder.map { Set([$0.occurrenceID]) } ?? []
        let existingIDs = Set(pendingReminders.map(\.occurrenceID))
            .union(deliveredThisLaunch)
            .union(presentedIDs)
        pendingReminders.append(
            contentsOf: evaluations.compactMap { evaluation in
                guard case let .present(reminder) = evaluation else {
                    return nil
                }
                guard !existingIDs.contains(reminder.occurrenceID) else {
                    return nil
                }
                return reminder
            }
        )
        pendingReminders.sort { $0.triggerDate < $1.triggerDate }
        scheduleNextWake(from: evaluations)
        presentNextIfNeeded()
    }

    private func scheduleNextWake(from evaluations: [ReminderScheduler.Evaluation]) {
        let nextDate = evaluations.compactMap { evaluation -> Date? in
            guard case let .scheduled(_, date) = evaluation else {
                return nil
            }
            return date
        }.min()

        guard let nextDate else {
            wakeTimer.cancel()
            return
        }
        wakeTimer.schedule(at: nextDate) { [weak self] in
            self?.wakeForScheduledReminders()
        }
    }

    private func wakeForScheduledReminders() {
        do {
            let evaluations = try scheduler.rebuildSchedule(from: Array(knownReminders.values))
            apply(evaluations)
        } catch {
            wakeTimer.cancel()
        }
    }

    private func presentNextIfNeeded() {
        guard !windowController.isVisible, !pendingReminders.isEmpty else {
            return
        }
        let reminder = pendingReminders.removeFirst()
        guard isSessionActive else {
            handleUnavailable(reminder)
            return
        }
        windowController.present(
            reminder,
            onDismiss: { [weak self] in
                self?.dismissCurrentReminder()
            },
            onSnooze: { [weak self] in
                self?.snoozeCurrentReminder()
            },
            onOpen: { [weak self] in
                self?.openCurrentReminderSource()
            },
            onAction: { [weak self] action in
                self?.performCurrentReminderAction(action)
            },
            onPresentationResult: { [weak self] isAvailable in
                self?.handlePresentationResult(isAvailable, reminder: reminder)
            }
        )
    }

    private func handlePresentationResult(_ isAvailable: Bool, reminder: Reminder) {
        if isAvailable {
            try? scheduler.markPresented(reminder.occurrenceID)
            if deliveredThisLaunch.insert(reminder.occurrenceID).inserted {
                if reminderSound.isEnabled {
                    soundPlayer.play(reminderSound)
                }
                onReminderPresented?(reminder)
            }
            return
        }
        windowController.dismiss()
        handleUnavailable(reminder)
    }

    private func handleUnavailable(_ reminder: Reminder) {
        guard reminder.presentationMode == .overlayWithNotificationFallback,
              fallbackInFlight.insert(reminder.occurrenceID).inserted else {
            requeue(reminder)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let delivered = await notificationFallback.deliver(reminder)
            fallbackInFlight.remove(reminder.occurrenceID)
            if delivered {
                try? scheduler.markPresented(reminder.occurrenceID)
                deliveredThisLaunch.insert(reminder.occurrenceID)
                presentNextIfNeeded()
            } else {
                requeue(reminder)
            }
        }
    }

    private func requeue(_ reminder: Reminder) {
        guard !pendingReminders.contains(where: { $0.occurrenceID == reminder.occurrenceID }) else {
            return
        }
        pendingReminders.append(reminder)
        pendingReminders.sort { $0.triggerDate < $1.triggerDate }
    }
}

extension ReminderPresentationCoordinator: CalendarReminderConsumer {}
