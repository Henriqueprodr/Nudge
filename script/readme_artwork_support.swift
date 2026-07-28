import AppKit
import Foundation

enum NudgeArtworkPalette {
    static func color(_ hexadecimal: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            deviceRed: CGFloat((hexadecimal >> 16) & 0xFF) / 255,
            green: CGFloat((hexadecimal >> 8) & 0xFF) / 255,
            blue: CGFloat(hexadecimal & 0xFF) / 255,
            alpha: alpha
        )
    }
}

enum NudgeArtworkBackground {
    static func drawHero(in context: CGContext, canvas: NSRect) {
        drawBase(
            in: context,
            canvas: canvas,
            gridRect: NSRect(x: 720, y: 60, width: 1_280, height: 880),
            blueGlow: (CGPoint(x: 1_670, y: 610), 690),
            coralGlow: (CGPoint(x: 1_140, y: 160), 520),
            goldGlow: (CGPoint(x: 1_920, y: 160), 430)
        )
    }

    static func drawGallery(in context: CGContext, canvas: NSRect) {
        let maximumDimension = max(canvas.width, canvas.height)
        drawBase(
            in: context,
            canvas: canvas,
            gridRect: canvas.insetBy(dx: 28, dy: 28),
            blueGlow: (
                CGPoint(x: canvas.width * 0.83, y: canvas.height * 0.61),
                maximumDimension * 0.44
            ),
            coralGlow: (
                CGPoint(x: canvas.width * 0.57, y: canvas.height * 0.16),
                maximumDimension * 0.30
            ),
            goldGlow: (
                CGPoint(x: canvas.width * 0.96, y: canvas.height * 0.16),
                maximumDimension * 0.25
            )
        )
        drawVignette(in: context, canvas: canvas)
    }

    private static func drawBase(
        in context: CGContext,
        canvas: NSRect,
        gridRect: NSRect,
        blueGlow: (center: CGPoint, radius: CGFloat),
        coralGlow: (center: CGPoint, radius: CGFloat),
        goldGlow: (center: CGPoint, radius: CGFloat)
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NudgeArtworkPalette.color(0x071327).cgColor,
                NudgeArtworkPalette.color(0x0A2348).cgColor,
                NudgeArtworkPalette.color(0x0A386A).cgColor,
            ] as CFArray,
            locations: [0, 0.56, 1]
        )
        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: canvas.minX, y: canvas.midY),
                end: CGPoint(x: canvas.maxX, y: canvas.midY),
                options: []
            )
        }

        drawRadialGlow(
            in: context,
            center: blueGlow.center,
            radius: blueGlow.radius,
            color: NudgeArtworkPalette.color(0x3187E8, alpha: 0.28)
        )
        drawRadialGlow(
            in: context,
            center: coralGlow.center,
            radius: coralGlow.radius,
            color: NudgeArtworkPalette.color(0xEC6A59, alpha: 0.12)
        )
        drawRadialGlow(
            in: context,
            center: goldGlow.center,
            radius: goldGlow.radius,
            color: NudgeArtworkPalette.color(0xF5B54A, alpha: 0.10)
        )

        context.saveGState()
        context.clip(to: gridRect)
        context.setStrokeColor(
            NudgeArtworkPalette.color(0xD7E9FF, alpha: 0.055).cgColor
        )
        context.setLineWidth(1)
        for x in stride(from: gridRect.minX, through: gridRect.maxX, by: 80) {
            context.move(to: CGPoint(x: x, y: gridRect.minY))
            context.addLine(to: CGPoint(x: x, y: gridRect.maxY))
        }
        for y in stride(from: gridRect.minY, through: gridRect.maxY, by: 80) {
            context.move(to: CGPoint(x: gridRect.minX, y: y))
            context.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawRadialGlow(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: NSColor
    ) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1]
        )
        if let gradient {
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: []
            )
        }
    }

    private static func drawVignette(in context: CGContext, canvas: NSRect) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NudgeArtworkPalette.color(0x000000, alpha: 0).cgColor,
                NudgeArtworkPalette.color(0x000000, alpha: 0.20).cgColor,
            ] as CFArray,
            locations: [0.66, 1]
        )
        if let gradient {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: canvas.midX, y: canvas.midY),
                startRadius: 0,
                endCenter: CGPoint(x: canvas.midX, y: canvas.midY),
                endRadius: max(canvas.width, canvas.height) * 0.68,
                options: [.drawsAfterEndLocation]
            )
        }
    }
}
