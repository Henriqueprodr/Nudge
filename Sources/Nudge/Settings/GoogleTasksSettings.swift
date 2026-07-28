import Foundation

struct GoogleTasksSettings: Codable, Equatable, Sendable {
    static let defaultPeriodicRefreshInterval = PeriodicRefreshInterval(minutes: 15)

    var schemaVersion: Int
    var periodicRefreshInterval: PeriodicRefreshInterval

    static let defaultValue = GoogleTasksSettings(
        schemaVersion: 1,
        periodicRefreshInterval: defaultPeriodicRefreshInterval
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case periodicRefreshInterval
    }

    init(schemaVersion: Int, periodicRefreshInterval: PeriodicRefreshInterval) {
        self.schemaVersion = schemaVersion
        self.periodicRefreshInterval = periodicRefreshInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        periodicRefreshInterval = try container.decodeIfPresent(
            PeriodicRefreshInterval.self,
            forKey: .periodicRefreshInterval
        ) ?? Self.defaultPeriodicRefreshInterval
    }
}
