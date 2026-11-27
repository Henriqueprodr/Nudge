import AppKit
import Foundation

/// Nudge brand colours, matching `NudgePalette` in the app's design system.
enum NudgeArtworkPalette {
    static let blue = 0x4A90E2
    static let green = 0x7FBA00
    static let ink = 0x2C3E50
    static let paper = 0xF8FAFB

    static func color(_ hexadecimal: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            deviceRed: CGFloat((hexadecimal >> 16) & 0xFF) / 255,
            green: CGFloat((hexadecimal >> 8) & 0xFF) / 255,
            blue: CGFloat(hexadecimal & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Deterministic hand-drawn shapes in the style of the app's `InkShape` and `WavyUnderline`.
enum NudgeInk {
    /// A rounded rectangle whose four corners differ slightly, like `InkShape`.
    static func unevenRoundedRect(
        _ rect: NSRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + bottomLeft, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - bottomRight, y: rect.minY))
        path.appendArc(
            from: NSPoint(x: rect.maxX, y: rect.minY),
            to: NSPoint(x: rect.maxX, y: rect.minY + bottomRight),
            radius: bottomRight
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - topRight))
        path.appendArc(
            from: NSPoint(x: rect.maxX, y: rect.maxY),
            to: NSPoint(x: rect.maxX - topRight, y: rect.maxY),
            radius: topRight
        )
        path.line(to: NSPoint(x: rect.minX + topLeft, y: rect.maxY))
        path.appendArc(
            from: NSPoint(x: rect.minX, y: rect.maxY),
            to: NSPoint(x: rect.minX, y: rect.maxY - topLeft),
            radius: topLeft
        )
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + bottomLeft))
        path.appendArc(
            from: NSPoint(x: rect.minX, y: rect.minY),
            to: NSPoint(x: rect.minX + bottomLeft, y: rect.minY),
            radius: bottomLeft
        )
        path.close()
        return path
    }

    /// A gentle sine-wave stroke between two x positions, like `WavyUnderline`.
    static func wavyLine(
        fromX startX: CGFloat,
        toX endX: CGFloat,
        y: CGFloat,
        amplitude: CGFloat,
        wavelength: CGFloat
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: startX, y: y))
        var x = startX
        while x < endX {
            x = min(x + 2, endX)
            let phase = (x - startX) / wavelength * 2 * .pi
            path.line(to: NSPoint(x: x, y: y + sin(phase) * amplitude))
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    /// Fills and outlines `path` with a solid, offset ink shadow, like the app's sticker cards.
    static func drawSticker(
        _ path: NSBezierPath,
        fill: NSColor,
        lineWidth: CGFloat,
        shadowOffset: NSSize
    ) {
        let shadowPath = path.copy() as! NSBezierPath
        shadowPath.transform(
            using: AffineTransform(translationByX: shadowOffset.width, byY: shadowOffset.height)
        )
        NudgeArtworkPalette.color(NudgeArtworkPalette.ink).setFill()
        shadowPath.fill()

        fill.setFill()
        path.fill()
        NudgeArtworkPalette.color(NudgeArtworkPalette.ink).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

/// The shared paper-and-grid backdrop for the README hero and the screenshot gallery.
enum NudgeArtworkBackground {
    static func drawHero(in context: CGContext, canvas: NSRect) {
        drawPaper(
            in: context,
            canvas: canvas,
            gridSpacing: 40,
            blueGlow: (CGPoint(x: 1_500, y: 560), 760),
            greenGlow: (CGPoint(x: 160, y: 80), 520)
        )
    }

    static func drawGallery(in context: CGContext, canvas: NSRect) {
        let maximumDimension = max(canvas.width, canvas.height)
        drawPaper(
            in: context,
            canvas: canvas,
            gridSpacing: 40,
            blueGlow: (
                CGPoint(x: canvas.width * 0.78, y: canvas.height * 0.70),
                maximumDimension * 0.62
            ),
            greenGlow: (
                CGPoint(x: canvas.width * 0.12, y: canvas.height * 0.08),
                maximumDimension * 0.42
            )
        )
    }

    private static func drawPaper(
        in context: CGContext,
        canvas: NSRect,
        gridSpacing: CGFloat,
        blueGlow: (center: CGPoint, radius: CGFloat),
        greenGlow: (center: CGPoint, radius: CGFloat)
    ) {
        NudgeArtworkPalette.color(NudgeArtworkPalette.paper).setFill()
        canvas.fill()

        drawRadialGlow(
            in: context,
            center: blueGlow.center,
            radius: blueGlow.radius,
            color: NudgeArtworkPalette.color(NudgeArtworkPalette.blue, alpha: 0.20)
        )
        drawRadialGlow(
            in: context,
            center: greenGlow.center,
            radius: greenGlow.radius,
            color: NudgeArtworkPalette.color(NudgeArtworkPalette.green, alpha: 0.13)
        )

        context.saveGState()
        context.setStrokeColor(
            NudgeArtworkPalette.color(NudgeArtworkPalette.blue, alpha: 0.10).cgColor
        )
        context.setLineWidth(1)
        for x in stride(from: canvas.minX + gridSpacing / 2, through: canvas.maxX, by: gridSpacing) {
            context.move(to: CGPoint(x: x, y: canvas.minY))
            context.addLine(to: CGPoint(x: x, y: canvas.maxY))
        }
        for y in stride(from: canvas.minY + gridSpacing / 2, through: canvas.maxY, by: gridSpacing) {
            context.move(to: CGPoint(x: canvas.minX, y: y))
            context.addLine(to: CGPoint(x: canvas.maxX, y: y))
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
}

/// A native transparent capture cropped to its visible pixels (including any window shadow).
struct NudgeTrimmedCapture {
    enum LoadError: LocalizedError {
        case missing(String)
        case unreadable(String)
        case empty(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name):
                return "Required native capture is missing: \(name)"
            case .unreadable(let name):
                return "Native capture is not a readable PNG: \(name)"
            case .empty(let name):
                return "Native capture has no visible pixels: \(name)"
            }
        }
    }

    let image: NSImage
    let size: NSSize

    init(url: URL) throws {
        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missing(name)
        }
        guard let data = try? Data(contentsOf: url),
              let source = NSBitmapImageRep(data: data),
              let cgImage = source.cgImage
        else {
            throw LoadError.unreadable(name)
        }
        guard let bounds = Self.visibleBounds(of: cgImage),
              let cropped = cgImage.cropping(to: bounds)
        else {
            throw LoadError.empty(name)
        }
        size = NSSize(width: cropped.width, height: cropped.height)
        let image = NSImage(size: size)
        image.addRepresentation(NSBitmapImageRep(cgImage: cropped))
        self.image = image
    }

    func draw(in destination: NSRect) {
        image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    /// Aspect-fits the capture inside `bounds`, centred, and returns where it was drawn.
    func fittedRect(in bounds: NSRect, maximumScale: CGFloat = 1) -> NSRect {
        let scale = min(bounds.width / size.width, bounds.height / size.height, maximumScale)
        let width = (size.width * scale).rounded()
        let height = (size.height * scale).rounded()
        return NSRect(
            x: (bounds.midX - width / 2).rounded(),
            y: (bounds.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    private static func visibleBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for row in 0..<height {
            let rowOffset = row * width * 4
            for column in 0..<width where pixels[rowOffset + column * 4 + 3] > 4 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return nil
        }
        // Bitmap-context memory rows run top-down, matching CGImage cropping.
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
