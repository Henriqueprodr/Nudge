import CoreGraphics
import Foundation
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
        /// Tapping the beak on the alert while clinging to it.
        case pecking
    }

    enum BubblePlacement: Equatable, Sendable {
        /// Above the bird, tail pointing down (Dock visits).
        case above
        /// Left of the bird, top-aligned with it so it grows downwards (alert perch).
        case leading
        /// Under the alert card, starting at the bird's left edge (alert perch, narrow screens).
        case belowCard(topY: CGFloat)
    }

    var isVisible = false
    var opacity: Double = 0
    var position: CGPoint = .zero
    var facesLeft = false
    var motion: Motion = .standing
    var isTalking = false
    var scale: CGFloat = 1
    var speech: String?
    /// When the current line began its word-by-word reveal; `nil` shows it all at once.
    var speechStart: Date?
    var bubblePlacement: BubblePlacement = .above
    /// Gripping a vertical edge (the alert's side) instead of standing.
    var isClinging = false
    /// Reference-date seconds when the current pecking run began, so pecks line up with sound.
    var peckStart: TimeInterval = 0

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
