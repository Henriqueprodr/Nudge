import CoreGraphics

/// What Nudge knows about the Dock without Accessibility access.
struct DockGeometry: Equatable, Sendable {
    enum Edge: String, Equatable, Sendable {
        case bottom
        case left
        case right
    }

    var edge: Edge
    var autohides: Bool
    /// Estimated width of the visible Dock along a bottom edge, in points.
    var estimatedLength: CGFloat?
}
