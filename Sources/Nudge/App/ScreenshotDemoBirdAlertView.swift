#if DEBUG
import SwiftUI

/// Screenshot-only scene: the reminder strip with the bird clinging to its left edge and
/// talking, laid out with the same perch geometry and bubble placement as `MascotController`
/// but frozen in a single pose so every capture is identical.
struct ScreenshotDemoBirdAlertView: View {
    let store: ReminderOverlayStore
    let line: String

    /// The perched bird is drawn at the controller's perch scale.
    private static let birdScale: CGFloat = 0.8

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ReminderOverlayView(
                store: store,
                onDismiss: {},
                onSnooze: {},
                onOpen: {},
                onAction: { _ in }
            )
            .fixedSize()
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    perchedBird(card: proxy.size)
                }
            }
        }
        .padding(.trailing, 24)
        .frame(maxHeight: .infinity)
    }

    private func perchedBird(card: CGSize) -> some View {
        let birdSize = CGSize(
            width: MascotScene.birdWidth * Self.birdScale,
            height: MascotScene.birdWidth * Self.birdScale
                * BirdShapes.canvas.height / BirdShapes.canvas.width
        )
        // Mirrors `MascotAlertPerch`: the feet grip just below the card's middle and overlap
        // its ink border.
        let cardBottom = card.height - InkMetrics.stickerOffset
        let gripY = min(
            cardBottom / 2 + MascotAlertPerch.gripBelowMiddle,
            cardBottom - MascotAlertPerch.cornerClearance
        )
        let birdFrame = CGRect(
            x: MascotAlertPerch.gripOverlap - birdSize.width * BirdShapes.clingGrip.x,
            y: gripY - birdSize.height * BirdShapes.clingGrip.y,
            width: birdSize.width,
            height: birdSize.height
        )
        var pose = BirdPose()
        pose.isClinging = true
        pose.tilt = MascotSceneView.clingingTilt
        pose.isLookingAtViewer = true
        pose.isBeakOpen = true

        return ZStack(alignment: .topLeading) {
            BirdView(pose: pose)
                .frame(width: birdSize.width, height: birdSize.height)
                .position(x: birdFrame.midX, y: birdFrame.midY)
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(alignment: .topTrailing) {
                    MascotSpeechBubble(text: line, tailEdge: .trailing, tailPosition: 0)
                        .fixedSize()
                }
                .position(x: birdFrame.minX - 12, y: birdFrame.minY - 4)
        }
    }
}
#endif
