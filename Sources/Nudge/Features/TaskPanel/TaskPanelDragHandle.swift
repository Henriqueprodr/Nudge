import AppKit
import SwiftUI

struct TaskPanelDragHandle: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    let onPressedChanged: (Bool) -> Void

    func makeNSView(context: Context) -> TaskPanelDraggingView {
        let view = TaskPanelDraggingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: TaskPanelDraggingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: TaskPanelDraggingView) {
        view.onHoverChanged = onHoverChanged
        view.onPressedChanged = onPressedChanged
    }
}

final class TaskPanelDraggingView: NSView {
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onPressedChanged: (Bool) -> Void = { _ in }
    var performWindowDrag: (NSWindow, NSEvent) -> Void = { window, event in
        window.performDrag(with: event)
    }

    private var pointerTrackingArea: NSTrackingArea?
    private(set) var isPointerInside = false
    private(set) var isPressed = false

    override func updateTrackingAreas() {
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        onHoverChanged(true)
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        onHoverChanged(false)
        if !isPressed {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        isPressed = true
        onPressedChanged(true)
        updateCursor()
        performWindowDrag(window, event)
        isPressed = false
        onPressedChanged(false)
        updateCursor()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isPressed ? .closedHand : .openHand)
    }

    private func updateCursor() {
        (isPressed ? NSCursor.closedHand : NSCursor.openHand).set()
    }
}
