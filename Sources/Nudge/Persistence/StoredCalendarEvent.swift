import Foundation
import SwiftData

@Model
final class StoredCalendarEvent {
    @Attribute(.unique) var cacheKey: String
    var payload: Data

    init(cacheKey: String, payload: Data) {
        self.cacheKey = cacheKey
        self.payload = payload
    }
}
