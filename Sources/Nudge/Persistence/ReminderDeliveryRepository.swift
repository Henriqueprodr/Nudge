@MainActor
protocol ReminderDeliveryRepository {
    func deliveryRecord(for occurrenceID: ReminderOccurrenceID) throws -> ReminderDeliveryRecord?
    func save(_ record: ReminderDeliveryRecord) throws
}
