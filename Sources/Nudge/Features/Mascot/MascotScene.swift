import CoreGraphics
import Observation

/// Observable state the mascot view draws. Coordinates are local to the mascot window, with
/// the origin at the top-left (SwiftUI convention); `position` is where the feet touch down.
@MainActor
@Observable
final class MascotScene {
    enum Motion: Equatable, Sendable {
        case standing
        case walking
        case flying
        case lookingAtViewer
    }

    enum BubblePlacement: Equatable, Sendable {
        case above
        case leading
        case below
    }

    var isVisible = false
    var opacity: Double = 0
    var position: CGPoint = .zero
    var facesLeft = false
    var motion: Motion = .standing
    var isTalking = false
    var scale: CGFloat = 1
    var speech: String?
    var bubblePlacement: BubblePlacement = .above

    static let birdWidth: CGFloat = 54

    var birdSize: CGSize {
        CGSize(
            width: Self.birdWidth * scale,
            height: Self.birdWidth * scale * BirdShapes.canvas.height / BirdShapes.canvas.width
        )
    }

    /// The bird's bounds in window-local coordinates.
    var birdFrame: CGRect {
        let size = birdSize
        return CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}
