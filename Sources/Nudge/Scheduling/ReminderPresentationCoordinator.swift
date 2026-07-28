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
        knownReminders = knownReminders.filter { occurrenceID, _ in
            occurrenceID.sourceKind != .calendar
        }
        pendingReminders.removeAll { reminder in
            reminder.occurrenceID.sourceKind == .calendar
        }
        try process(reminders)
    }

    func dismissCurrentReminder() {
        guard let reminder = windowController.presentedReminder else {
            return
        }
        try? scheduler.dismiss(reminder.occurrenceID)
        windowController.dismiss()
        presentNextIfNeeded()
    }

    func snoozeCurrentReminder(for interval: TimeInterval = 10 * 60) {
        guard let reminder = windowController.presentedReminder else {
            return
        }
        windowController.beginAction()
        do {
            try scheduler.snooze(reminder.occurrenceID, until: now().addingTimeInterval(interval))
            deliveredThisLaunch.remove(reminder.occurrenceID)
            pendingReminders.removeAll { $0.occurrenceID == reminder.occurrenceID }
            windowController.dismiss()
            let evaluations = try scheduler.rebuildSchedule(from: Array(knownReminders.values))
            apply(evaluations)
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
            onPresentationResult: { [weak self] isAvailable in
                self?.handlePresentationResult(isAvailable, reminder: reminder)
            }
        )
    }

    private func handlePresentationResult(_ isAvailable: Bool, reminder: Reminder) {
        if isAvailable {
            try? scheduler.markPresented(reminder.occurrenceID)
            if deliveredThisLaunch.insert(reminder.occurrenceID).inserted,
               reminderSound.isEnabled {
                soundPlayer.play(reminderSound)
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
