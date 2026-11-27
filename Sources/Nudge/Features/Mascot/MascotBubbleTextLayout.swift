import SwiftUI

/// Sizes the speech bubble's text the same way for every proposal, including the `nil`
/// proposal `.fixedSize()` sends.
///
/// Short lines keep their natural width. Longer lines wrap at `maxWidth`, then the width is
/// narrowed as far as it can go without adding a line, so the last line isn't one stray word.
/// The reported height is always the wrapped text's real height, so the bubble fits its words.
struct MascotBubbleTextLayout: Layout {
    var maxWidth: CGFloat = 260
    /// The narrowest width the balancing search may try, as a fraction of `maxWidth`.
    var minimumBalanceFraction: CGFloat = 0.6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        return Self.size(of: text, maxWidth: maxWidth, minimumFraction: minimumBalanceFraction)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let text = subviews.first else { return }
        text.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }

    private static func size(
        of text: LayoutSubview,
        maxWidth: CGFloat,
        minimumFraction: CGFloat
    ) -> CGSize {
        let ideal = text.sizeThatFits(.unspecified)
        if ideal.width <= maxWidth {
            return CGSize(width: ceil(ideal.width), height: ceil(ideal.height))
        }
        func height(at width: CGFloat) -> CGFloat {
            text.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let targetHeight = height(at: maxWidth)
        var fits = maxWidth
        var tooNarrow = maxWidth * minimumFraction
        if height(at: tooNarrow) <= targetHeight {
            fits = tooNarrow
        } else {
            for _ in 0..<6 {
                let middle = (fits + tooNarrow) / 2
                if height(at: middle) <= targetHeight {
                    fits = middle
                } else {
                    tooNarrow = middle
                }
            }
        }
        let width = ceil(fits)
        return CGSize(width: width, height: ceil(height(at: width)))
    }
}
