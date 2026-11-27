import SwiftUI

/// Draws the bird and its speech bubble inside the transparent mascot window.
struct MascotSceneView: View {
    let scene: MascotScene
    var onPoke: () -> Void = {}
    var onMute: () -> Void = {}
    var onGoAwayToday: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The root is always exactly the window's size. The bird and its bubble each sit in
        // their own overlay, and an overlay never resizes its parent, so a bubble poking past an
        // edge can't shift the bird or feed a size change back into AppKit (that feedback loop
        // crashed the app with "more Update Constraints passes than views" on every perch).
        Color.clear
            .overlay(alignment: .topLeading) { birdLayer }
            .overlay(alignment: .topLeading) { bubbleLayer }
            .opacity(scene.opacity)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var birdLayer: some View {
        if scene.isVisible {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating)) { context in
                BirdView(
                    pose: pose(at: context.date.timeIntervalSinceReferenceDate),
                    facesLeft: scene.facesLeft
                )
                .frame(width: scene.birdSize.width, height: scene.birdSize.height)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPoke)
            .contextMenu {
                Button("Mute the Bird for 1 Hour", action: onMute)
                Button("Go Away for Today", action: onGoAwayToday)
            }
            .position(x: scene.position.x, y: scene.position.y - scene.birdSize.height / 2)
        }
    }

    @ViewBuilder
    private var bubbleLayer: some View {
        if scene.isVisible, let speech = scene.speech {
            bubble(speech)
                .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
        }
    }

    private var isAnimating: Bool {
        guard !reduceMotion else { return scene.isTalking }
        return scene.motion == .walking || scene.motion == .flying || scene.isTalking
    }

    private func pose(at time: TimeInterval) -> BirdPose {
        var pose = BirdPose()
        let blinkPhase = time.truncatingRemainder(dividingBy: 3.4)
        pose.isBlinking = blinkPhase < 0.12
        switch scene.motion {
        case .standing:
            break
        case .walking:
            pose.legSwing = reduceMotion ? 0 : CGFloat(sin(time * 13) * 0.8)
            pose.bob = reduceMotion ? 0 : CGFloat(abs(sin(time * 13)) * 1.8)
        case .flying:
            pose.areLegsTucked = true
            pose.wingLift = reduceMotion ? 0.5 : CGFloat((sin(time * 20) + 1) / 2)
            pose.bob = reduceMotion ? 0 : CGFloat(sin(time * 20) * 1.5)
        case .lookingAtViewer:
            pose.isLookingAtViewer = true
        }
        if scene.isTalking {
            pose.isBeakOpen = sin(time * 16) > 0
            if scene.motion == .lookingAtViewer {
                pose.bob = CGFloat(sin(time * 8) * 0.6)
            }
        }
        return pose
    }

    /// Pins the bubble to a zero-size anchor beside the bird. The bubble is fixed-size, so it
    /// overflows the anchor in the chosen direction without affecting any layout around it.
    private func bubble(_ text: String) -> some View {
        let bird = scene.birdFrame
        let anchor: CGPoint
        let alignment: Alignment
        let tailEdge: Edge
        switch scene.bubblePlacement {
        case .above:
            anchor = CGPoint(x: bird.midX, y: bird.minY - 10)
            alignment = .bottom
            tailEdge = .bottom
        case .leading:
            anchor = CGPoint(x: bird.minX - 12, y: bird.midY)
            alignment = .trailing
            tailEdge = .trailing
        case .below:
            anchor = CGPoint(x: bird.midX, y: bird.maxY + 12)
            alignment = .top
            tailEdge = .top
        }
        return Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: alignment) {
                MascotSpeechBubble(text: text, tailEdge: tailEdge)
                    .fixedSize()
            }
            .position(anchor)
    }
}
