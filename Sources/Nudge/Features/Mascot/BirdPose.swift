import CoreGraphics

/// Everything that varies frame to frame when drawing the bird.
struct BirdPose: Equatable, Sendable {
    /// -1...1 swing of the near leg; the far leg mirrors it.
    var legSwing: CGFloat = 0
    /// 0 (folded) ... 1 (raised).
    var wingLift: CGFloat = 0
    /// Vertical body bob in canvas units (positive is down).
    var bob: CGFloat = 0
    /// Faces the viewer with both eyes instead of showing its profile.
    var isLookingAtViewer = false
    /// Eyes closed for a blink.
    var isBlinking = false
    /// Beak opened slightly while talking or whistling.
    var isBeakOpen = false
    /// Legs tucked up while flying.
    var areLegsTucked = false

    static let standing = BirdPose()
}
