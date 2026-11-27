import AppKit
import SwiftUI

/// Every styling constant for the reminder control strip.
///
/// The strip is sized by its content, so these values are limited to spacing, semantic
/// typography, colour, and the two documented width bounds that keep the layout stable for very
/// short and very long event titles.
enum ReminderStripStyle {
    // MARK: Layout

    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    /// Space between the time, event-content, and action regions.
    static let regionSpacing: CGFloat = 14
    static let timeChipMinimumWidth: CGFloat = 78
    /// Space between stacked lines inside the time and event-content regions.
    static let lineSpacing: CGFloat = 3
    static let actionSpacing: CGFloat = 8

    /// Keeps a two-word event from collapsing into a cramped sliver.
    static let minimumWidth: CGFloat = 450
    /// Upper bound for a long title before it truncates, so the strip keeps a control-strip
    /// silhouette instead of stretching across the display. The controller narrows this further
    /// when the display is small.
    static let maximumWidth: CGFloat = 700

    /// Distance from the visible frame's top and horizontal edges. The top inset leaves room for
    /// the mascot to perch on the card without covering the menu bar.
    static let screenTopInset: CGFloat = 44
    static let screenHorizontalInset: CGFloat = 8

    // MARK: Typography

    static let timeFont = Font.system(.title3, design: .rounded).weight(.heavy).monospacedDigit()
    static let dateFont = Font.system(.caption2, design: .rounded).weight(.heavy)
    static let eyebrowFont = InkMetrics.eyebrowFont
    static let titleFont = Font.system(.title2, design: .rounded).weight(.bold)
    static let metadataFont = Font.system(.body, design: .rounded)
    static let eyebrowTracking: CGFloat = InkMetrics.eyebrowTracking

    // MARK: Colour

    static let primaryText = NudgePalette.ink
    static let secondaryText = NudgePalette.inkSecondary

    static let warningText = NudgePalette.red

    // MARK: Motion

    static let entryDuration: TimeInterval = 0.28
    static let exitDuration: TimeInterval = 0.22
    /// Reduced-motion presentations fade without travelling across the display.
    static let reducedMotionDuration: TimeInterval = 0.18
    static let transitionScale: CGFloat = 0.94
    static let entryBounce: Double = 0.12

    /// Resolves a `#rrggbb` or `#rrggbbaa` calendar colour, falling back to the strip accent.
    static func accentColor(hex: String) -> Color {
        guard let color = Self.color(fromHex: hex) else {
            return Self.color(fromHex: ReminderStripPresentation.fallbackAccentHex)
                ?? Color.secondary
        }
        return color
    }

    static func color(fromHex hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6 || value.count == 8,
              let raw = UInt64(value, radix: 16) else {
            return nil
        }
        let hasAlpha = value.count == 8
        let red = Double((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(raw & 0xFF) / 255 : 1
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
