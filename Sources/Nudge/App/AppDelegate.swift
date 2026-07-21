import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Phase 0 deliberately starts as a menu-bar-only utility. A later setting
        // may switch between accessory and regular activation policies.
        NSApp.setActivationPolicy(.accessory)
    }
}
