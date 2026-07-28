import Foundation

enum GoogleCalendarRefreshTrigger: String, CaseIterable, Sendable {
    case launch
    case authentication
    case wake
    case manual
    case settingsChange
    case periodic
}
