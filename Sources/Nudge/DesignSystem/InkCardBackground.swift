import SwiftUI

/// Paper surface with a navy ink outline and a solid offset "sticker" shadow.
struct InkCardBackground: View {
    var variant: InkShape.Variant = .card
    var fill: Color = NudgePalette.paper
    var showsStickerShadow = true

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            if showsStickerShadow {
                InkShape(variant: variant)
                    .fill(NudgePalette.stickerShadow)
                    .offset(y: InkMetrics.stickerOffset)
            }
            InkShape(variant: variant)
                .fill(fill)
            InkShape(variant: variant)
                .strokeBorderCompatible(NudgePalette.ink, lineWidth: strokeWidth)
        }
        .accessibilityHidden(true)
    }

    private var strokeWidth: CGFloat {
        colorSchemeContrast == .increased ? InkMetrics.contrastStrokeWidth : InkMetrics.strokeWidth
    }
}
