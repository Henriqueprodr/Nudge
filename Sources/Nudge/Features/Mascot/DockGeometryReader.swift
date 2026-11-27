import AppKit

/// Reads the Dock's orientation, auto-hide, and an estimate of its width from its preferences.
///
/// macOS does not expose the Dock's frame without Accessibility permission. The width is
/// estimated from the tile count (pinned apps, running apps, folders, recents, Trash) and the
/// visible Dock thickness, which is accurate to within a tile or two.
@MainActor
struct DockGeometryReader {
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) {
        self.defaults = defaults
    }

    func read(dockThickness: CGFloat) -> DockGeometry {
        let edge = DockGeometry.Edge(rawValue: defaults?.string(forKey: "orientation") ?? "bottom")
            ?? .bottom
        let autohides = defaults?.bool(forKey: "autohide") ?? false
        return DockGeometry(
            edge: edge,
            autohides: autohides,
            estimatedLength: estimatedLength(dockThickness: dockThickness)
        )
    }

    private func estimatedLength(dockThickness: CGFloat) -> CGFloat? {
        guard dockThickness > 8 else { return nil }
        let pinned = (defaults?.array(forKey: "persistent-apps") ?? []).compactMap(bundleIdentifier)
        let others = defaults?.array(forKey: "persistent-others")?.count ?? 0
        let pinnedSet = Set(pinned)
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinnedSet.contains($0.bundleIdentifier ?? "")
        }.count
        let showsRecents = defaults?.object(forKey: "show-recents") as? Bool ?? true
        let recents = showsRecents ? 3 : 0
        // Finder is always present; Trash always present.
        let tiles = max(pinned.count, 1) + running + recents + others + 1
        let separators = 1 + (recents > 0 ? 1 : 0)
        let tile = dockThickness * 0.84
        return CGFloat(tiles) * tile + CGFloat(separators) * tile * 0.35 + tile * 0.4
    }

    private func bundleIdentifier(_ entry: Any) -> String? {
        guard let entry = entry as? [String: Any],
              let tileData = entry["tile-data"] as? [String: Any] else { return nil }
        return tileData["bundle-identifier"] as? String
    }
}
