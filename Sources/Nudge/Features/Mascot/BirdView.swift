import SwiftUI

/// Draws the Nudge bird in the "sticker" style: logo-blue fill and navy ink outlines.
struct BirdView: View {
    var pose: BirdPose = .standing
    /// Faces right when `false`, left when `true`.
    var facesLeft = false

    private let fill = Color(nsColor: NudgePalette.blueNSColor)
    private let ink = Color(nsColor: NudgePalette.inkNSColor)
    private let paper = Color(nsColor: NudgePalette.paperNSColor)

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let lineWidth = max(proxy.size.width * 0.045, 1.5)
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            ZStack {
                if !pose.areLegsTucked {
                    legs(stroke: stroke)
                }
                Group {
                    BirdBodyShape().fill(fill)
                    BirdBodyShape().stroke(ink, style: stroke)
                    if pose.isLookingAtViewer {
                        BirdFrontBeakShape().fill(paper)
                        BirdFrontBeakShape().stroke(ink, style: stroke)
                    } else {
                        BirdBeakShape()
                            .fill(paper)
                            .rotationEffect(
                                .degrees(pose.isBeakOpen ? -8 : 0),
                                anchor: UnitPoint(x: 0.8, y: 0.19)
                            )
                        BirdBeakShape()
                            .stroke(ink, style: stroke)
                            .rotationEffect(
                                .degrees(pose.isBeakOpen ? -8 : 0),
                                anchor: UnitPoint(x: 0.8, y: 0.19)
                            )
                    }
                    if pose.areLegsTucked {
                        BirdFlyingWingShape(lift: pose.wingLift).fill(fill)
                        BirdFlyingWingShape(lift: pose.wingLift).stroke(ink, style: stroke)
                    } else {
                        BirdWingShape(lift: pose.wingLift).stroke(ink, style: stroke)
                    }
                    eyes(in: rect)
                }
                .offset(y: pose.bob / BirdShapes.canvas.height * proxy.size.height)
                if pose.areLegsTucked {
                    tuckedLegs(stroke: stroke)
                        .offset(y: pose.bob / BirdShapes.canvas.height * proxy.size.height)
                }
            }
            .scaleEffect(x: facesLeft ? -1 : 1, y: 1)
        }
        .aspectRatio(BirdShapes.canvas, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func legs(stroke: StrokeStyle) -> some View {
        let footStroke = StrokeStyle(lineWidth: stroke.lineWidth * 0.75, lineCap: .round)
        BirdLegShape(hipX: 41, footX: 35, swing: -pose.legSwing).stroke(ink, style: stroke)
        BirdLegShape(hipX: 55, footX: 55.5, swing: pose.legSwing).stroke(ink, style: stroke)
        BirdFootShape(heelX: 36, reach: -12, swing: -pose.legSwing).fill(paper)
        BirdFootShape(heelX: 36, reach: -12, swing: -pose.legSwing).stroke(ink, style: footStroke)
        BirdFootShape(heelX: 54, reach: 13, swing: pose.legSwing).fill(paper)
        BirdFootShape(heelX: 54, reach: 13, swing: pose.legSwing).stroke(ink, style: footStroke)
    }

    private func tuckedLegs(stroke: StrokeStyle) -> some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            Path { path in
                path.move(to: BirdShapes.point(42, 82, in: rect))
                path.addLine(to: BirdShapes.point(32, 92, in: rect))
                path.move(to: BirdShapes.point(54, 82, in: rect))
                path.addLine(to: BirdShapes.point(44, 93, in: rect))
            }
            .stroke(ink, style: stroke)
        }
    }

    @ViewBuilder
    private func eyes(in rect: CGRect) -> some View {
        let eyeWidth = 3.6 / BirdShapes.canvas.width * rect.width
        let eyeHeight = (pose.isBlinking ? 1 : 6.5) / BirdShapes.canvas.height * rect.height
        let eyeCenters: [CGPoint] = pose.isLookingAtViewer
            ? [BirdShapes.point(60, 17, in: rect), BirdShapes.point(74, 17, in: rect)]
            : [BirdShapes.point(70, 16, in: rect)]
        ForEach(Array(eyeCenters.enumerated()), id: \.offset) { _, center in
            Capsule()
                .fill(ink)
                .frame(width: eyeWidth, height: eyeHeight)
                .position(center)
        }
    }
}
