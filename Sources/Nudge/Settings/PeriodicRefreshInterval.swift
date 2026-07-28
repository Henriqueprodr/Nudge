import Foundation

struct PeriodicRefreshInterval: Codable, Equatable, Sendable {
    static let allowedMinutes = 5...60
    static let defaultValue = PeriodicRefreshInterval(minutes: 5)

    let minutes: Int

    init(minutes: Int) {
        self.minutes = min(max(minutes, Self.allowedMinutes.lowerBound), Self.allowedMinutes.upperBound)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(minutes: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutes)
    }

    var timeInterval: TimeInterval {
        TimeInterval(minutes * 60)
    }
}
