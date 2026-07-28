import Foundation
import SwiftData

@Model
final class StoredCalendarDescriptor {
    @Attribute(.unique) var identifier: String
    var payload: Data

    init(identifier: String, payload: Data) {
        self.identifier = identifier
        self.payload = payload
    }
}
