import SwiftUI

/// Shared stroke widths, offsets, and type for the hand-drawn style.
enum InkMetrics {
    static let strokeWidth: CGFloat = 2.5
    static let contrastStrokeWidth: CGFloat = 3.5
    static let thinStrokeWidth: CGFloat = 2
    /// Vertical offset of the solid sticker shadow under cards and buttons.
    static let stickerOffset: CGFloat = 3

    static let titleFont = Font.system(.title3, design: .rounded).weight(.bold)
    static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .rounded)
    static let eyebrowFont = Font.system(.caption, design: .rounded).weight(.heavy)
    static let captionFont = Font.system(.caption, design: .rounded).weight(.medium)
    static let eyebrowTracking: CGFloat = 0.8
}
