import Foundation
import SwiftData

@Model
final class StoredCalendarSyncMetadata {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String = "google-calendar", payload: Data) {
        self.key = key
        self.payload = payload
    }
}
