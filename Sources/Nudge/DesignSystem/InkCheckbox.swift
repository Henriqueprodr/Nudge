import SwiftUI

/// A hand-drawn square checkbox: ink outline, green tick when checked.
struct InkCheckbox: View {
    var isChecked: Bool
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            InkShape(variant: .checkbox)
                .fill(isChecked ? NudgePalette.green : NudgePalette.paper)
            InkShape(variant: .checkbox)
                .strokeBorderCompatible(NudgePalette.ink, lineWidth: InkMetrics.thinStrokeWidth)
            if isChecked {
                InkTick()
                    .stroke(
                        NudgePalette.onFill,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                    .padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A slightly lopsided check mark.
struct InkTick: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY + rect.height * 0.3)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.midY - rect.height * 0.1)
        )
        return path
    }
}
