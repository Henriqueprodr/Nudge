import AppKit

final class ReminderOverlayWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // Keep the reminder flush with its border; neither AppKit nor SwiftUI draws a shadow.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .alertPanel
    }
}
