import SwiftUI

/// A hand-drawn speech bubble whose words fade in one after another.
struct MascotSpeechBubble: View {
    let text: String
    var tailEdge: Edge = .bottom
    /// Where the tail sits along its edge: 0 is the top or leading end, 1 the bottom or trailing.
    var tailPosition: CGFloat = 0.5
    /// When the word-by-word reveal began; `nil` shows the whole line at once.
    var revealStart: Date?

    private let ink = Color(nsColor: NudgePalette.inkNSColor)

    var body: some View {
        MascotBubbleTextLayout {
            revealingText
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background {
            InkCardBackground(variant: .chip, fill: Color(nsColor: .white))
                .environment(\.colorScheme, .light)
        }
        .overlay {
            GeometryReader { proxy in
                tail.position(tailCenter(in: proxy.size))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nudge bird says: \(text)")
    }

    @ViewBuilder
    private var revealingText: some View {
        if let revealStart {
            let reveal = MascotSpeechReveal(text: text)
            TimelineView(.explicit(reveal.frameDates(from: revealStart))) { context in
                Text(reveal.attributedText(
                    elapsed: context.date.timeIntervalSince(revealStart),
                    color: ink
                ))
            }
        } else {
            Text(text).foregroundStyle(ink)
        }
    }

    private var tail: some View {
        BubbleTail(edge: tailEdge)
            .fill(Color.white)
            .overlay(BubbleTail(edge: tailEdge).stroke(
                ink,
                style: StrokeStyle(lineWidth: InkMetrics.thinStrokeWidth, lineJoin: .round)
            ))
            .frame(width: tailSize.width, height: tailSize.height)
    }

    private var tailSize: CGSize {
        tailEdge.isHorizontal ? CGSize(width: 10, height: 14) : CGSize(width: 14, height: 10)
    }

    /// The tail straddles the bubble's border, pointing outwards from `tailEdge`.
    private func tailCenter(in size: CGSize) -> CGPoint {
        let inset: CGFloat = 16
        let alongX = inset + (size.width - inset * 2) * tailPosition
        let alongY = inset + (size.height - inset * 2) * tailPosition
        switch tailEdge {
        case .bottom: return CGPoint(x: alongX, y: size.height + 3)
        case .top: return CGPoint(x: alongX, y: -3)
        case .leading: return CGPoint(x: -3, y: alongY)
        case .trailing: return CGPoint(x: size.width + 3, y: alongY)
        }
    }
}

private extension Edge {
    var isHorizontal: Bool {
        self == .leading || self == .trailing
    }
}

/// A small triangle pointing away from the bubble toward the bird.
private struct BubbleTail: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch edge {
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - 2, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + 2))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}
