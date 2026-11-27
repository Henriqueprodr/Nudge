import SwiftUI

/// A hand-drawn speech bubble.
struct MascotSpeechBubble: View {
    let text: String
    var tailEdge: Edge = .bottom

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .foregroundStyle(Color(nsColor: NudgePalette.inkNSColor))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 230, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background {
                InkCardBackground(variant: .chip, fill: Color(nsColor: .white))
                    .environment(\.colorScheme, .light)
            }
            .overlay(alignment: tailAlignment) {
                BubbleTail(edge: tailEdge)
                    .fill(Color.white)
                    .overlay(BubbleTail(edge: tailEdge).stroke(
                        Color(nsColor: NudgePalette.inkNSColor),
                        style: StrokeStyle(lineWidth: InkMetrics.thinStrokeWidth, lineJoin: .round)
                    ))
                    .frame(width: tailEdge.isHorizontal ? 10 : 14, height: tailEdge.isHorizontal ? 14 : 10)
                    .offset(tailOffset)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Nudge bird says: \(text)")
    }

    private var tailAlignment: Alignment {
        switch tailEdge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private var tailOffset: CGSize {
        switch tailEdge {
        case .bottom: return CGSize(width: 0, height: 8)
        case .top: return CGSize(width: 0, height: -8)
        case .leading: return CGSize(width: -8, height: 0)
        case .trailing: return CGSize(width: 8, height: 0)
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
