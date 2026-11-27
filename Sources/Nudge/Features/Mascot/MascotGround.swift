import CoreGraphics

/// Where the bird can stand on a display, in global screen coordinates.
struct MascotGround: Equatable, Sendable {
    /// The y coordinate of the surface the bird's feet rest on.
    let y: CGFloat
    /// The horizontal stretch it can walk along.
    let xRange: ClosedRange<CGFloat>
    /// `true` when standing on top of a bottom Dock.
    let isOnDock: Bool

    /// Margin so the bird never walks off the end of the Dock.
    static let dockEndInset: CGFloat = 36
    static let screenEdgeInset: CGFloat = 70

    /// A bottom, visible Dock is walked along its top edge; otherwise the bird walks along the
    /// bottom of the screen.
    static func resolve(frame: CGRect, visibleFrame: CGRect, dock: DockGeometry) -> MascotGround {
        let dockThickness = visibleFrame.minY - frame.minY
        if dock.edge == .bottom, !dock.autohides, dockThickness > 8 {
            let length = min(dock.estimatedLength ?? frame.width * 0.5, frame.width)
            let half = max(length / 2 - dockEndInset, 40)
            let lower = frame.midX - half
            let upper = frame.midX + half
            return MascotGround(y: visibleFrame.minY, xRange: lower...upper, isOnDock: true)
        }
        let lower = visibleFrame.minX + screenEdgeInset
        let upper = max(visibleFrame.maxX - screenEdgeInset, lower + 1)
        return MascotGround(y: visibleFrame.minY, xRange: lower...upper, isOnDock: false)
    }
}
