import Observation
import ServiceManagement

enum LaunchAtLoginServiceStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginManager.Status { get }
    func refreshStatus()
    func setEnabled(_ isEnabled: Bool)
    func openSystemSettings()
}

@MainActor
@Observable
final class LaunchAtLoginManager: LaunchAtLoginManaging {
    enum Status: Equatable, Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case unavailable
        case failed(String)

        var isEnabled: Bool {
            self == .enabled || self == .requiresApproval
        }

        var message: String {
            switch self {
            case .notRegistered:
                return "Launch at login is off."
            case .enabled:
                return "Nudge will launch when you sign in."
            case .requiresApproval:
                return "Allow Nudge in System Settings > Login Items."
            case .unavailable:
                return "Launch at login is unavailable for this app bundle."
            case let .failed(message):
                return message
            }
        }
    }

    private let service: any LaunchAtLoginService
    private(set) var status: Status = .notRegistered

    init(service: any LaunchAtLoginService = MainAppLaunchAtLoginService()) {
        self.service = service
        refreshStatus()
    }

    func refreshStatus() {
        switch service.status {
        case .notRegistered:
            status = .notRegistered
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        case .unavailable:
            status = .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            if status != .requiresApproval {
                status = .failed(
                    isEnabled
                        ? "Launch at login could not be enabled."
                        : "Launch at login could not be disabled."
                )
            }
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

@MainActor
final class MainAppLaunchAtLoginService: LaunchAtLoginService {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginServiceStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
