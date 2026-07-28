import AppKit
import SwiftUI

/// Every styling constant for the reminder control strip.
///
/// The strip is sized by its content, so these values are limited to spacing, semantic
/// typography, colour, and the two documented width bounds that keep the layout stable for very
/// short and very long event titles.
enum ReminderStripStyle {
    // MARK: Layout

    /// Width of the calendar-colour accent along the leading edge.
    static let accentWidth: CGFloat = 5
    static let cornerRadius: CGFloat = 13
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 13
    /// Space between the time, event-content, and action regions.
    static let regionSpacing: CGFloat = 18
    /// Space between stacked lines inside the time and event-content regions.
    static let lineSpacing: CGFloat = 3
    static let actionSpacing: CGFloat = 8
    static let minimumActionHeight: CGFloat = 35

    /// Keeps a two-word event from collapsing into a cramped sliver.
    static let minimumWidth: CGFloat = 450
    /// Upper bound for a long title before it truncates, so the strip keeps a control-strip
    /// silhouette instead of stretching across the display. The controller narrows this further
    /// when the display is small.
    static let maximumWidth: CGFloat = 700

    /// Distance from the visible frame's top and horizontal edges.
    static let screenTopInset: CGFloat = 8
    static let screenHorizontalInset: CGFloat = 8

    // MARK: Typography

    static let timeFont = Font.title2.weight(.medium).monospacedDigit()
    static let dateFont = Font.caption.weight(.semibold)
    static let eyebrowFont = Font.caption.weight(.semibold)
    static let titleFont = Font.title2.weight(.semibold)
    static let metadataFont = Font.body
    static let eyebrowTracking: CGFloat = 0.7

    // MARK: Colour

    /// Opaque semantic fallback used when Reduce Transparency is enabled.
    static let opaqueSurface = dynamicColor(
        light: NSColor(srgbRed: 0.965, green: 0.965, blue: 0.970, alpha: 1),
        dark: NSColor(srgbRed: 0.145, green: 0.145, blue: 0.155, alpha: 1)
    )

    static let border = dynamicColor(
        light: NSColor(srgbRed: 0.000, green: 0.000, blue: 0.000, alpha: 0.12),
        dark: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 0.14)
    )

    static let contrastBorder = Color.primary.opacity(0.65)

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary

    static let divider = dynamicColor(
        light: NSColor(srgbRed: 0.000, green: 0.000, blue: 0.000, alpha: 0.10),
        dark: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 0.12)
    )

    static let warningText = Color(nsColor: .systemOrange)

    static let borderWidth: CGFloat = 1
    static let contrastBorderWidth: CGFloat = 2

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

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? dark : light
            }
        )
    }
}
