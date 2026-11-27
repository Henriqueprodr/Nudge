import SwiftUI

/// `InkShape` inset by a fixed amount so outlines can be stroked inside their bounds.
struct InsetInkShape: InsettableShape {
    var base: InkShape
    var amount: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect.insetBy(dx: amount, dy: amount))
    }

    func inset(by amount: CGFloat) -> InsetInkShape {
        InsetInkShape(base: base, amount: self.amount + amount)
    }
}

extension InkShape: InsettableShape {
    func inset(by amount: CGFloat) -> InsetInkShape {
        InsetInkShape(base: self, amount: amount)
    }
}

extension InsettableShape {
    /// Strokes inside the shape's bounds with round caps, so outlines never clip at a window edge.
    func strokeBorderCompatible(_ color: Color, lineWidth: CGFloat) -> some View {
        strokeBorder(
            color,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
