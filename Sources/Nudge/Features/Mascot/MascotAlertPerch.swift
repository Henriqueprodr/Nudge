import CoreGraphics

/// Where the bird clings to an alert's left edge, like a woodpecker on a trunk, and where its
/// speech bubble goes.
///
/// Inputs are in AppKit screen coordinates (origin bottom-left). Outputs are local to the
/// mascot window, which covers `screenFrame` with a top-left origin, matching `MascotScene`.
struct MascotAlertPerch: Equatable, Sendable {
    /// Clear space needed beside the bird for a `.leading` bubble.
    static let leadingBubbleSpace: CGFloat = 300
    /// Minimum gap between the bird and the screen edge.
    static let edgeMargin: CGFloat = 12
    /// How far the bird's feet overlap the card's ink border.
    static let gripOverlap: CGFloat = 1
    /// Minimum gap between the bird and the menu bar.
    static let topMargin: CGFloat = 4
    /// How far below the card's vertical middle the feet grip.
    static let gripBelowMiddle: CGFloat = 8
    /// Minimum distance between the feet and the card's bottom, clear of its rounded corner.
    static let cornerClearance: CGFloat = 16

    /// Where the bird's feet touch down (bottom-centre of its frame), in window-local points.
    let position: CGPoint
    /// The bird's frame, in window-local points.
    let birdFrame: CGRect
    let bubblePlacement: MascotScene.BubblePlacement
    /// The card's vertical middle, in window-local points; the fly-in and exit paths use it.
    let cardMidY: CGFloat

    init?(card: CGRect, screenFrame: CGRect, visibleFrame: CGRect, birdSize: CGSize) {
        func localX(_ x: CGFloat) -> CGFloat { x - screenFrame.minX }
        func localY(_ y: CGFloat) -> CGFloat { screenFrame.maxY - y }

        let spaceOnLeading = card.minX - visibleFrame.minX
        guard spaceOnLeading >= birdSize.width + Self.edgeMargin else { return nil }

        let cardLeft = localX(card.minX)
        let cardTop = localY(card.maxY)
        let cardBottom = localY(card.minY)
        let visibleTop = localY(visibleFrame.maxY)
        let mid = (cardTop + cardBottom) / 2
        // Feet grip just below the card's middle, on the straight part of its border, clear of
        // the rounded corners; the bird never rises closer than `topMargin` to the menu bar.
        let gripY = min(mid + Self.gripBelowMiddle, cardBottom - Self.cornerClearance)
        let birdTop = max(
            gripY - birdSize.height * BirdShapes.clingGrip.y,
            visibleTop + Self.topMargin
        )
        let frame = CGRect(
            x: cardLeft + Self.gripOverlap - birdSize.width * BirdShapes.clingGrip.x,
            y: birdTop,
            width: birdSize.width,
            height: birdSize.height
        )
        birdFrame = frame
        position = CGPoint(x: frame.midX, y: frame.maxY)
        cardMidY = mid
        let roomBesideBird = frame.minX - localX(visibleFrame.minX)
        bubblePlacement = roomBesideBird >= Self.leadingBubbleSpace
            ? .leading
            : .belowCard(topY: cardBottom + 12)
    }
}
