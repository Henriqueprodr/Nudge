import Foundation

struct ReminderDeliveryRecord: Codable, Hashable, Sendable {
    enum State: String, Codable, Hashable, Sendable {
        case scheduled
        case presented
        case dismissed
        case snoozed
        case acted
        case expired
    }

    let occurrenceID: ReminderOccurrenceID
    var state: State
    var scheduledAt: Date?
    var presentedAt: Date?
    var snoozedUntil: Date?
    var updatedAt: Date
}
