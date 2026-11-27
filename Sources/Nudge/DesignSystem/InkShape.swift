import SwiftUI

/// A rounded rectangle with slightly uneven corners, so outlined surfaces read as hand-drawn
/// like the Nudge logo rather than machine-perfect.
struct InkShape: Shape {
    enum Variant: Sendable {
        case card
        case panel
        case chip
        case button
        case checkbox
    }

    var variant: Variant = .card

    func path(in rect: CGRect) -> Path {
        let radii = cornerRadii
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }

    private var cornerRadii: RectangleCornerRadii {
        switch variant {
        case .card:
            return RectangleCornerRadii(
                topLeading: 18, bottomLeading: 15, bottomTrailing: 19, topTrailing: 16
            )
        case .panel:
            return RectangleCornerRadii(
                topLeading: 16, bottomLeading: 19, bottomTrailing: 15, topTrailing: 18
            )
        case .chip:
            return RectangleCornerRadii(
                topLeading: 11, bottomLeading: 9, bottomTrailing: 12, topTrailing: 10
            )
        case .button:
            return RectangleCornerRadii(
                topLeading: 10, bottomLeading: 8, bottomTrailing: 10, topTrailing: 9
            )
        case .checkbox:
            return RectangleCornerRadii(
                topLeading: 6, bottomLeading: 4.5, bottomTrailing: 6.5, topTrailing: 5
            )
        }
    }
}
