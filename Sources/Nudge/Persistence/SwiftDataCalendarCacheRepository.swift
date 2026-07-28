import Foundation
import SwiftData

@MainActor
final class SwiftDataCalendarCacheRepository: CalendarCacheRepository {
    private let modelContext: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchCalendars() throws -> [CalendarDescriptor] {
        try modelContext.fetch(FetchDescriptor<StoredCalendarDescriptor>())
            .compactMap { try? decoder.decode(CalendarDescriptor.self, from: $0.payload) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func replaceCalendars(_ calendars: [CalendarDescriptor]) throws {
        let encoded = try calendars.map { ($0.id, try encoder.encode($0)) }
        for value in try modelContext.fetch(FetchDescriptor<StoredCalendarDescriptor>()) {
            modelContext.delete(value)
        }
        for value in encoded {
            modelContext.insert(StoredCalendarDescriptor(identifier: value.0, payload: value.1))
        }
        try modelContext.save()
    }

    func fetchEvents() throws -> [CalendarEventSnapshot] {
        try modelContext.fetch(FetchDescriptor<StoredCalendarEvent>())
            .compactMap { try? decoder.decode(CalendarEventSnapshot.self, from: $0.payload) }
    }

    func replaceEvents(_ events: [CalendarEventSnapshot]) throws {
        let encoded = try events.map { event in
            let key = [
                event.calendarIdentifier,
                event.recurringEventIdentifier ?? event.eventIdentifier,
                event.stableOccurrenceValue,
            ].joined(separator: "|")
            return (key, try encoder.encode(event))
        }
        for value in try modelContext.fetch(FetchDescriptor<StoredCalendarEvent>()) {
            modelContext.delete(value)
        }
        for value in encoded {
            modelContext.insert(StoredCalendarEvent(cacheKey: value.0, payload: value.1))
        }
        try modelContext.save()
    }

    func fetchMetadata() throws -> SyncMetadata? {
        guard let value = try modelContext.fetch(
            FetchDescriptor<StoredCalendarSyncMetadata>()
        ).first else {
            return nil
        }
        return try decoder.decode(SyncMetadata.self, from: value.payload)
    }

    func saveMetadata(_ metadata: SyncMetadata) throws {
        let payload = try encoder.encode(metadata)
        if let value = try modelContext.fetch(
            FetchDescriptor<StoredCalendarSyncMetadata>()
        ).first {
            value.payload = payload
        } else {
            modelContext.insert(StoredCalendarSyncMetadata(payload: payload))
        }
        try modelContext.save()
    }
}
