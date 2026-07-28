import AppKit
import SwiftUI

enum TaskPriorityColor {
    static func color(hex: String) -> Color {
        guard let color = nsColor(hex: hex) else {
            return .clear
        }
        return Color(nsColor: color)
    }

    static func hex(color: Color, fallback: String) -> String {
        let nsColor = NSColor(color)
        guard let converted = nsColor.usingColorSpace(.sRGB) else {
            return fallback
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(converted.redComponent * 255)),
            Int(round(converted.greenComponent * 255)),
            Int(round(converted.blueComponent * 255))
        )
    }

    private static func nsColor(hex: String) -> NSColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let raw = UInt64(value, radix: 16) else {
            return nil
        }
        return NSColor(
            srgbRed: CGFloat((raw >> 16) & 0xFF) / 255,
            green: CGFloat((raw >> 8) & 0xFF) / 255,
            blue: CGFloat(raw & 0xFF) / 255,
            alpha: 1
        )
    }
}
