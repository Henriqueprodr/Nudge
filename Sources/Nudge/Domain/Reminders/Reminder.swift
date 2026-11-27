import Foundation

struct Reminder: Codable, Hashable, Sendable {
    enum PresentationMode: String, Codable, Hashable, Sendable {
        case overlay
        case overlayWithNotificationFallback
    }

    let occurrenceID: ReminderOccurrenceID
    let title: String
    let detail: String?
    let triggerDate: Date
    let expirationDate: Date?
    let presentationMode: PresentationMode
    var sourceURL: URL? = nil
    var eventContext: ReminderEventContext? = nil
    var taskContext: ReminderTaskContext? = nil
    var actions: [ReminderAction] = []
}
