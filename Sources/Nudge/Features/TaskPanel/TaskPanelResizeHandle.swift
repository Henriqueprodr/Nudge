import AppKit
import SwiftUI

enum TaskPanelResizeEdge: Equatable, Sendable {
    case top
    case bottom

    var overlayAlignment: Alignment {
        switch self {
        case .top:
            .top
        case .bottom:
            .bottom
        }
    }
}

struct TaskPanelResizeHandle: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    let onDragBegan: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> TaskPanelResizeTrackingView {
        let view = TaskPanelResizeTrackingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: TaskPanelResizeTrackingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: TaskPanelResizeTrackingView) {
        view.onHoverChanged = onHoverChanged
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
    }
}

final class TaskPanelResizeTrackingView: NSView {
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onDragBegan: () -> Void = {}
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private var pointerTrackingArea: NSTrackingArea?
    private var startingScreenY: CGFloat?
    private(set) var isPointerInside = false
    private(set) var isDragging = false

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
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        onHoverChanged(false)
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseDown(with event: NSEvent) {
        startingScreenY = screenY(for: event)
        isDragging = true
        NSCursor.resizeUpDown.set()
        onDragBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startingScreenY else {
            return
        }
        NSCursor.resizeUpDown.set()
        onDragChanged(screenY(for: event) - startingScreenY)
    }

    override func mouseUp(with event: NSEvent) {
        guard startingScreenY != nil else {
            return
        }
        startingScreenY = nil
        isDragging = false
        onDragEnded()
        (isPointerInside ? NSCursor.resizeUpDown : NSCursor.arrow).set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    private func screenY(for event: NSEvent) -> CGFloat {
        guard let window else {
            return event.locationInWindow.y
        }
        return window.convertPoint(toScreen: event.locationInWindow).y
    }
}
