import Foundation

enum GoogleTasksRefreshTrigger: String, CaseIterable, Sendable {
    case launch
    case authentication
    case wake
    case manual
    case periodic
    case postAction
}
