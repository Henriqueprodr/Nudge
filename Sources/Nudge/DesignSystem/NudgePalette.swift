import AppKit
import SwiftUI

/// The Nudge brand palette (from `brand/`), with dark-mode counterparts.
///
/// - Logo blue `#4A90E2`: brand, mascot, links, selection.
/// - Accent green `#7FBA00`: primary actions and completion.
/// - Ink navy `#2C3E50`: text and the hand-drawn outlines.
/// - Paper `#F8FAFB`: surfaces.
enum NudgePalette {
    static let blueHex = "#4A90E2"
    static let greenHex = "#7FBA00"
    static let inkHex = "#2C3E50"
    static let paperHex = "#F8FAFB"
    static let redHex = "#D9534F"

    static let blue = Color(nsColor: blueNSColor)
    static let green = Color(nsColor: greenNSColor)
    static let red = Color(nsColor: NSColor(srgbHex: redHex))

    static let blueNSColor = NSColor(srgbHex: blueHex)
    static let greenNSColor = NSColor(srgbHex: greenHex)
    static let inkNSColor = NSColor(srgbHex: inkHex)
    static let paperNSColor = NSColor(srgbHex: paperHex)

    /// Outlines and primary text: navy on light, paper on dark.
    static let ink = dynamic(light: inkNSColor, dark: paperNSColor)
    /// Secondary text.
    static let inkSecondary = dynamic(
        light: NSColor(srgbRed: 0.36, green: 0.43, blue: 0.50, alpha: 1),
        dark: NSColor(srgbRed: 0.72, green: 0.78, blue: 0.84, alpha: 1)
    )
    /// Card surface: paper on light, deep navy on dark.
    static let paper = dynamic(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.137, green: 0.192, blue: 0.247, alpha: 1)
    )
    /// Slightly tinted surface for rows, wells, and the settings background.
    static let paperTint = dynamic(
        light: paperNSColor,
        dark: NSColor(srgbRed: 0.106, green: 0.153, blue: 0.200, alpha: 1)
    )
    /// The solid offset "sticker" shadow under ink cards.
    static let stickerShadow = dynamic(
        light: inkNSColor,
        dark: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.10, alpha: 1)
    )
    /// Text on green and blue fills.
    static let onFill = Color(nsColor: inkNSColor)
    static let onBlue = Color.white

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        )
    }
}

extension NSColor {
    /// Creates an sRGB colour from `#rrggbb`. Invalid input yields black.
    convenience init(srgbHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        let raw = UInt64(value, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((raw >> 16) & 0xFF) / 255,
            green: CGFloat((raw >> 8) & 0xFF) / 255,
            blue: CGFloat(raw & 0xFF) / 255,
            alpha: 1
        )
    }
}
