import Foundation

struct CalendarSettings: Codable, Equatable, Sendable {
    static let defaultPeriodicRefreshInterval = PeriodicRefreshInterval(minutes: 5)

    var schemaVersion: Int
    var selectedCalendarIdentifiers: Set<String>
    var hasConfiguredSelection: Bool
    var lookAheadDays: Int
    var usesNotificationFallback: Bool
    var periodicRefreshInterval: PeriodicRefreshInterval

    static let defaultValue = CalendarSettings(
        schemaVersion: 3,
        selectedCalendarIdentifiers: [],
        hasConfiguredSelection: false,
        lookAheadDays: 14,
        usesNotificationFallback: false,
        periodicRefreshInterval: defaultPeriodicRefreshInterval
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case selectedCalendarIdentifiers
        case hasConfiguredSelection
        case lookAheadDays
        case usesNotificationFallback
        case periodicRefreshInterval
    }

    init(
        schemaVersion: Int,
        selectedCalendarIdentifiers: Set<String>,
        hasConfiguredSelection: Bool,
        lookAheadDays: Int,
        usesNotificationFallback: Bool,
        periodicRefreshInterval: PeriodicRefreshInterval = defaultPeriodicRefreshInterval
    ) {
        self.schemaVersion = schemaVersion
        self.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        self.hasConfiguredSelection = hasConfiguredSelection
        self.lookAheadDays = lookAheadDays
        self.usesNotificationFallback = usesNotificationFallback
        self.periodicRefreshInterval = periodicRefreshInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        selectedCalendarIdentifiers = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .selectedCalendarIdentifiers
        ) ?? []
        hasConfiguredSelection = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasConfiguredSelection
        ) ?? false
        lookAheadDays = try container.decodeIfPresent(Int.self, forKey: .lookAheadDays) ?? 14
        usesNotificationFallback = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesNotificationFallback
        ) ?? false
        periodicRefreshInterval = try container.decodeIfPresent(
            PeriodicRefreshInterval.self,
            forKey: .periodicRefreshInterval
        ) ?? Self.defaultPeriodicRefreshInterval
    }
}
