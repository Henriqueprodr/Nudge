import Foundation

/// Decides when Nudge next nags about unfinished tasks, and which tasks that nag covers.
///
/// The policy is pure: it reads cached tasks, local nag history, settings, and the current time,
/// and makes no network calls. Cadence escalates automatically, so tasks never need their own
/// reminder settings:
///
/// | Task                               | Cadence                                 |
/// |------------------------------------|-----------------------------------------|
/// | Due today                          | 11:00 and 16:00 (high: 10, 13, 16)      |
/// | 1–2 days overdue                   | every 4 hours                           |
/// | 3–6 days overdue                   | every 2 hours                           |
/// | 7+ days overdue                    | every 90 minutes                        |
/// | Undated, open 3–13 days            | every 48 hours                          |
/// | Undated, open 14+ days             | every 24 hours                          |
///
/// High priority moves a task one step faster. Quiet hours, the daily limit, and the minimum
/// gap apply to all nags. Tasks that qualify at the same time share one alert.
struct TaskNagPolicy {
    struct Candidate: Equatable {
        let task: TaskItem
        let urgency: ReminderTaskContext.Urgency
        let daysOverdue: Int?
        let daysOpen: Int
        let dueAt: Date
        let score: Int
    }

    /// Nag times in the past are floored to this bucket so recomputing within a few minutes
    /// yields the same occurrence identity (and the scheduler deduplicates it).
    static let pastSlotBucket: TimeInterval = 10 * 60
    static let undatedGraceDays = 3
    static let undatedAncientDays = 14
    static let ancientOverdueDays = 7
    static let dueTodayHours = [11, 16]
    static let highPriorityDueTodayHours = [10, 13, 16]

    /// From slowest to fastest; urgency picks a starting step and high priority adds one.
    private static let cadenceLadder: [TimeInterval] = [
        48 * 3600, 24 * 3600, 4 * 3600, 2 * 3600, 90 * 60, 60 * 60,
    ]

    let settings: TaskNagSettings
    let calendar: Calendar

    init(settings: TaskNagSettings, calendar: Calendar = .current) {
        self.settings = settings.validated
        self.calendar = calendar
    }

    /// The next nag, or `nil` when nothing qualifies or nagging is off.
    func nextReminder(tasks: [TaskItem], history: TaskNagHistory, now: Date) -> Reminder? {
        guard settings.isEnabled else { return nil }
        let candidates = candidates(tasks: tasks, history: history, now: now)
        guard let earliestDue = candidates.map(\.dueAt).min(),
              let slot = slot(earliestDue: earliestDue, history: history, now: now) else {
            return nil
        }
        let batchCutoff = max(slot, now)
        let batch = candidates
            .filter { $0.dueAt <= batchCutoff }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.task.title.localizedStandardCompare(rhs.task.title) == .orderedAscending
            }
        guard let primary = batch.first else { return nil }

        return Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .task,
                sourceIdentifier: "task-nag:\(primary.task.id)",
                occurrenceDate: slot,
                revision: nil
            ),
            title: primary.task.title,
            detail: nil,
            triggerDate: slot,
            expirationDate: nil,
            presentationMode: .overlay,
            sourceURL: primary.task.webViewURL,
            taskContext: ReminderTaskContext(
                taskIDs: batch.map(\.task.id),
                primaryTaskListID: primary.task.taskListID,
                urgency: primary.urgency,
                dueDate: primary.task.dueDate,
                daysOverdue: primary.daysOverdue,
                daysOpen: primary.daysOpen
            ),
            actions: [.completeTask, .notToday]
        )
    }

    /// Every task that deserves a nag at some point, with the time it becomes due.
    func candidates(tasks: [TaskItem], history: TaskNagHistory, now: Date) -> [Candidate] {
        let today = calendar.startOfDay(for: now)
        return tasks.compactMap { task in
            candidate(for: task, observation: history.observations[task.id], today: today, now: now)
        }
    }

    // MARK: Per-task classification

    private func candidate(
        for task: TaskItem,
        observation: TaskNagObservation?,
        today: Date,
        now: Date
    ) -> Candidate? {
        guard task.isIncomplete, !task.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        if let snoozed = task.locallySnoozedUntil, snoozed > now { return nil }
        if let silenced = observation?.silencedUntil, silenced > now { return nil }

        let firstSeen = observation?.firstSeenAt ?? now
        let daysOpen = max(wholeDays(from: calendar.startOfDay(for: firstSeen), to: today), 0)
        let isHighPriority = task.priority == .high

        let urgency: ReminderTaskContext.Urgency
        let daysOverdue: Int?
        let ladderIndex: Int?

        if let dueDate = task.dueDate {
            guard let dueDay = calendar.date(
                from: DateComponents(year: dueDate.year, month: dueDate.month, day: dueDate.day)
            ) else { return nil }
            let overdue = wholeDays(from: calendar.startOfDay(for: dueDay), to: today)
            guard overdue >= 0 else { return nil }
            daysOverdue = overdue
            switch overdue {
            case 0:
                urgency = .dueToday
                ladderIndex = nil
            case 1...2:
                urgency = .overdue
                ladderIndex = 2
            case 3..<Self.ancientOverdueDays:
                urgency = .overdue
                ladderIndex = 3
            default:
                urgency = .ancient
                ladderIndex = 4
            }
        } else {
            guard settings.includesUndatedTasks, daysOpen >= Self.undatedGraceDays else {
                return nil
            }
            daysOverdue = nil
            urgency = daysOpen >= Self.undatedAncientDays ? .ancient : .lingering
            ladderIndex = daysOpen >= Self.undatedAncientDays ? 1 : 0
        }

        let dueAt: Date
        if let snoozedUntil = observation?.snoozedUntil {
            dueAt = snoozedUntil
        } else if let ladderIndex {
            let step = min(ladderIndex + (isHighPriority ? 1 : 0), Self.cadenceLadder.count - 1)
            if let lastNagged = observation?.lastNaggedAt {
                dueAt = lastNagged.addingTimeInterval(Self.cadenceLadder[step])
            } else {
                dueAt = max(activeStart(of: today), firstSeen)
            }
        } else {
            let hours = isHighPriority ? Self.highPriorityDueTodayHours : Self.dueTodayHours
            let slots = hours.compactMap { hour in
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)
            }
            let lastNagged = observation?.lastNaggedAt ?? .distantPast
            guard let nextSlot = slots.first(where: { $0 > lastNagged }) else {
                // Already nagged at every due-today slot; tomorrow it becomes overdue.
                return nil
            }
            dueAt = nextSlot
        }

        return Candidate(
            task: task,
            urgency: urgency,
            daysOverdue: daysOverdue,
            daysOpen: daysOpen,
            dueAt: dueAt,
            score: score(urgency: urgency, daysOverdue: daysOverdue, daysOpen: daysOpen, task: task)
        )
    }

    private func score(
        urgency: ReminderTaskContext.Urgency,
        daysOverdue: Int?,
        daysOpen: Int,
        task: TaskItem
    ) -> Int {
        let urgencyRank: Int
        switch urgency {
        case .ancient: urgencyRank = 3
        case .overdue: urgencyRank = 2
        case .dueToday: urgencyRank = 1
        case .lingering: urgencyRank = 0
        }
        let age = min(daysOverdue ?? daysOpen / 2, 99)
        let priorityBonus: Int
        switch task.priority {
        case .high: priorityBonus = 5
        case .medium: priorityBonus = 3
        case .low: priorityBonus = 1
        case .none: priorityBonus = 0
        }
        // A missed date the user chose outranks an undated task of similar age.
        let rank = daysOverdue == nil ? max(urgencyRank - 1, 0) : urgencyRank
        let datedBonus = daysOverdue == nil ? 0 : 200
        return rank * 1_000 + datedBonus + age * 10 + priorityBonus
    }

    // MARK: Global pacing

    private func slot(earliestDue: Date, history: TaskNagHistory, now: Date) -> Date? {
        var slot = earliestDue
        if let lastDelivered = history.lastDeliveredNagDate {
            let gap = TimeInterval(settings.minimumGapMinutes * 60)
            slot = max(slot, lastDelivered.addingTimeInterval(gap))
        }
        // Anything already due is due now; it still has to respect quiet hours and the limit.
        let isOverdueNow = slot <= now
        if isOverdueNow {
            slot = now
        }
        // A few passes settle quiet hours and the daily limit pushing each other forward.
        for _ in 0..<3 {
            slot = movedOutOfQuietHours(slot)
            if deliveries(onDayOf: slot, in: history) >= settings.dailyLimit {
                guard let nextDay = calendar.date(
                    byAdding: .day, value: 1, to: calendar.startOfDay(for: slot)
                ) else {
                    return nil
                }
                slot = activeStart(of: nextDay)
            }
        }
        if isOverdueNow, slot == now {
            let bucket = (now.timeIntervalSinceReferenceDate / Self.pastSlotBucket).rounded(.down)
            slot = Date(timeIntervalSinceReferenceDate: bucket * Self.pastSlotBucket)
        }
        return slot
    }

    private func deliveries(onDayOf date: Date, in history: TaskNagHistory) -> Int {
        history.deliveredNagDates.filter { calendar.isDate($0, inSameDayAs: date) }.count
    }

    /// When nagging may begin on `day` (the end of quiet hours).
    private func activeStart(of day: Date) -> Date {
        let start = calendar.startOfDay(for: day)
        guard settings.quietHoursStartHour != settings.quietHoursEndHour else { return start }
        return calendar.date(
            bySettingHour: settings.quietHoursEndHour, minute: 0, second: 0, of: start
        ) ?? start
    }

    func isInQuietHours(_ date: Date) -> Bool {
        let start = settings.quietHoursStartHour
        let end = settings.quietHoursEndHour
        guard start != end else { return false }
        let hour = calendar.component(.hour, from: date)
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }

    private func movedOutOfQuietHours(_ date: Date) -> Date {
        guard isInQuietHours(date) else { return date }
        let sameDayEnd = activeStart(of: date)
        if sameDayEnd > date { return sameDayEnd }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
            return date
        }
        return activeStart(of: nextDay)
    }

    private func wholeDays(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
