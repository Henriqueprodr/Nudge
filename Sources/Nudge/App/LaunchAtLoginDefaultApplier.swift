import Foundation

/// Turns launch at login on once, the first time an installed copy of Nudge runs.
///
/// Only bundles inside an `Applications` folder qualify, so Debug builds in DerivedData and
/// copies opened from Downloads never register themselves as login items. After the default
/// has been applied the user's own choice in Settings is authoritative and is never overridden.
@MainActor
struct LaunchAtLoginDefaultApplier {
    static let appliedDefaultsKey = "launchAtLogin.didApplyDefault"

    private let defaults: UserDefaults
    private let bundleURL: URL

    init(defaults: UserDefaults = .standard, bundleURL: URL = Bundle.main.bundleURL) {
        self.defaults = defaults
        self.bundleURL = bundleURL
    }

    var isInstalledCopy: Bool {
        let components = bundleURL.standardizedFileURL.pathComponents
        guard components.count >= 2 else { return false }
        return components[components.count - 2] == "Applications"
    }

    /// Returns `true` when this call enabled launch at login.
    @discardableResult
    func applyIfNeeded(to manager: any LaunchAtLoginManaging) -> Bool {
        guard isInstalledCopy, !defaults.bool(forKey: Self.appliedDefaultsKey) else {
            return false
        }
        defaults.set(true, forKey: Self.appliedDefaultsKey)
        manager.refreshStatus()
        guard manager.status == .notRegistered else { return false }
        manager.setEnabled(true)
        return true
    }
}
