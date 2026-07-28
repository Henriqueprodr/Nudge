import Foundation

@MainActor
protocol CalendarCacheRepository: AnyObject {
    func fetchCalendars() throws -> [CalendarDescriptor]
    func replaceCalendars(_ calendars: [CalendarDescriptor]) throws
    func fetchEvents() throws -> [CalendarEventSnapshot]
    func replaceEvents(_ events: [CalendarEventSnapshot]) throws
    func fetchMetadata() throws -> SyncMetadata?
    func saveMetadata(_ metadata: SyncMetadata) throws
}
