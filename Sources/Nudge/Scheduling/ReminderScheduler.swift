import Foundation

@MainActor
final class ReminderScheduler {
    struct Policy: Equatable, Sendable {
        var missedWindowGraceInterval: TimeInterval

        static let defaultValue = Policy(missedWindowGraceInterval: 15 * 60)
    }

    enum Evaluation: Equatable {
        case scheduled(ReminderOccurrenceID, Date)
        case present(Reminder)
        case expired(ReminderOccurrenceID)
        case ignored(ReminderOccurrenceID)
    }

    private let repository: any ReminderDeliveryRepository
    private let clock: any ReminderClock
    private let policy: Policy

    init(
        repository: any ReminderDeliveryRepository,
        clock: any ReminderClock = SystemReminderClock(),
        policy: Policy = .defaultValue
    ) {
        self.repository = repository
        self.clock = clock
        self.policy = policy
    }

    func rebuildSchedule(from reminders: [Reminder]) throws -> [Evaluation] {
        try reminders.map(evaluate)
    }

    func dismiss(_ occurrenceID: ReminderOccurrenceID) throws {
        guard var record = try repository.deliveryRecord(for: occurrenceID) else {
            return
        }
        record.state = .dismissed
        record.snoozedUntil = nil
        record.updatedAt = clock.now
        try repository.save(record)
    }

    func snooze(_ occurrenceID: ReminderOccurrenceID, until date: Date) throws {
        guard var record = try repository.deliveryRecord(for: occurrenceID) else {
            return
        }
        record.state = .snoozed
        record.snoozedUntil = date
        record.updatedAt = clock.now
        try repository.save(record)
    }

    func markActed(_ occurrenceID: ReminderOccurrenceID) throws {
        guard var record = try repository.deliveryRecord(for: occurrenceID) else {
            return
        }
        record.state = .acted
        record.snoozedUntil = nil
        record.updatedAt = clock.now
        try repository.save(record)
    }

    func markPresented(_ occurrenceID: ReminderOccurrenceID) throws {
        guard var record = try repository.deliveryRecord(for: occurrenceID) else {
            return
        }
        guard record.state == .scheduled || record.state == .presented else {
            return
        }
        record.state = .presented
        record.presentedAt = clock.now
        record.updatedAt = clock.now
        try repository.save(record)
    }

    private func evaluate(_ reminder: Reminder) throws -> Evaluation {
        let now = clock.now
        let existingRecord = try repository.deliveryRecord(for: reminder.occurrenceID)

        if let existingRecord {
            switch existingRecord.state {
            case .dismissed, .acted, .expired:
                return .ignored(reminder.occurrenceID)
            case .presented:
                break
            case .snoozed:
                guard let snoozedUntil = existingRecord.snoozedUntil else {
                    return .ignored(reminder.occurrenceID)
                }
                if now < snoozedUntil {
                    return .scheduled(reminder.occurrenceID, snoozedUntil)
                }
            case .scheduled:
                break
            }
        }

        let effectiveTriggerDate = existingRecord?.state == .snoozed
            ? existingRecord?.snoozedUntil ?? reminder.triggerDate
            : reminder.triggerDate

        if now < effectiveTriggerDate {
            let record = ReminderDeliveryRecord(
                occurrenceID: reminder.occurrenceID,
                state: .scheduled,
                scheduledAt: existingRecord?.scheduledAt ?? now,
                presentedAt: existingRecord?.presentedAt,
                snoozedUntil: existingRecord?.snoozedUntil,
                updatedAt: now
            )
            try repository.save(record)
            return .scheduled(reminder.occurrenceID, effectiveTriggerDate)
        }

        let graceExpirationDate = effectiveTriggerDate.addingTimeInterval(
            policy.missedWindowGraceInterval
        )
        let expirationDate = min(reminder.expirationDate ?? graceExpirationDate, graceExpirationDate)
        if now > expirationDate {
            let record = ReminderDeliveryRecord(
                occurrenceID: reminder.occurrenceID,
                state: .expired,
                scheduledAt: existingRecord?.scheduledAt,
                presentedAt: existingRecord?.presentedAt,
                snoozedUntil: existingRecord?.snoozedUntil,
                updatedAt: now
            )
            try repository.save(record)
            return .expired(reminder.occurrenceID)
        }

        if existingRecord?.state == .presented {
            return .present(reminder)
        }

        let record = ReminderDeliveryRecord(
            occurrenceID: reminder.occurrenceID,
            state: .scheduled,
            scheduledAt: existingRecord?.scheduledAt ?? now,
            presentedAt: existingRecord?.presentedAt,
            snoozedUntil: nil,
            updatedAt: now
        )
        try repository.save(record)
        return .present(reminder)
    }
}
