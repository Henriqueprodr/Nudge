import Foundation

struct ReminderPresentationDuration: Codable, Equatable, Sendable {
    static let allowedSeconds = 3...30
    static let defaultValue = ReminderPresentationDuration(seconds: 10)

    let seconds: Int

    init(seconds: Int) {
        self.seconds = min(max(seconds, Self.allowedSeconds.lowerBound), Self.allowedSeconds.upperBound)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(seconds: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }

    var timeInterval: TimeInterval {
        TimeInterval(seconds)
    }
}
