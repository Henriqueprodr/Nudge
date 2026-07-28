import Foundation
import SwiftData

@Model
final class StoredReminderDelivery {
    var sourceKindRawValue: String
    var sourceIdentifier: String
    var occurrenceDate: Date
    var revision: String?
    var stateRawValue: String
    var scheduledAt: Date?
    var presentedAt: Date?
    var snoozedUntil: Date?
    var updatedAt: Date

    init(record: ReminderDeliveryRecord) {
        sourceKindRawValue = record.occurrenceID.sourceKind.rawValue
        sourceIdentifier = record.occurrenceID.sourceIdentifier
        occurrenceDate = record.occurrenceID.occurrenceDate
        revision = record.occurrenceID.revision
        stateRawValue = record.state.rawValue
        scheduledAt = record.scheduledAt
        presentedAt = record.presentedAt
        snoozedUntil = record.snoozedUntil
        updatedAt = record.updatedAt
    }

    func matches(_ occurrenceID: ReminderOccurrenceID) -> Bool {
        sourceKindRawValue == occurrenceID.sourceKind.rawValue
            && sourceIdentifier == occurrenceID.sourceIdentifier
            && occurrenceDate == occurrenceID.occurrenceDate
            && revision == occurrenceID.revision
    }

    func update(from record: ReminderDeliveryRecord) {
        stateRawValue = record.state.rawValue
        scheduledAt = record.scheduledAt
        presentedAt = record.presentedAt
        snoozedUntil = record.snoozedUntil
        updatedAt = record.updatedAt
    }

    func domainValue() -> ReminderDeliveryRecord? {
        guard
            let sourceKind = ReminderOccurrenceID.SourceKind(rawValue: sourceKindRawValue),
            let state = ReminderDeliveryRecord.State(rawValue: stateRawValue)
        else {
            return nil
        }

        return ReminderDeliveryRecord(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: sourceKind,
                sourceIdentifier: sourceIdentifier,
                occurrenceDate: occurrenceDate,
                revision: revision
            ),
            state: state,
            scheduledAt: scheduledAt,
            presentedAt: presentedAt,
            snoozedUntil: snoozedUntil,
            updatedAt: updatedAt
        )
    }
}
