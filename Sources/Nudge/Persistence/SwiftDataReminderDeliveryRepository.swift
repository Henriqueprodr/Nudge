import SwiftData

@MainActor
final class SwiftDataReminderDeliveryRepository: ReminderDeliveryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func deliveryRecord(for occurrenceID: ReminderOccurrenceID) throws -> ReminderDeliveryRecord? {
        try modelContext.fetch(FetchDescriptor<StoredReminderDelivery>())
            .first(where: { $0.matches(occurrenceID) })?
            .domainValue()
    }

    func save(_ record: ReminderDeliveryRecord) throws {
        let records = try modelContext.fetch(FetchDescriptor<StoredReminderDelivery>())
        if let storedRecord = records.first(where: { $0.matches(record.occurrenceID) }) {
            storedRecord.update(from: record)
        } else {
            modelContext.insert(StoredReminderDelivery(record: record))
        }
        try modelContext.save()
    }
}
