import AppKit
import Foundation

private struct RasterAsset {
    let image: NSImage
    let pixelSize: NSSize

    init(url: URL, expectedPixelSize: NSSize) throws {
        guard let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data)
        else {
            throw GeneratorError.unreadableImage(url.lastPathComponent)
        }

        let actualSize = NSSize(
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        )
        guard actualSize == expectedPixelSize else {
            throw GeneratorError.unexpectedDimensions(
                name: url.lastPathComponent,
                expected: expectedPixelSize,
                actual: actualSize
            )
        }

        let image = NSImage(size: actualSize)
        image.addRepresentation(representation)
        self.image = image
        pixelSize = actualSize
    }
}

private enum GeneratorError: LocalizedError {
    case missingInput(String)
    case unreadableImage(String)
    case unexpectedDimensions(name: String, expected: NSSize, actual: NSSize)
    case contextCreationFailed
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let name):
            return "Required input is missing: \(name)"
        case .unreadableImage(let name):
            return "Required input is not a readable image: \(name)"
        case .unexpectedDimensions(let name, let expected, let actual):
            return "\(name) has dimensions \(Int(actual.width))x\(Int(actual.height)); expected \(Int(expected.width))x\(Int(expected.height))."
        case .contextCreationFailed:
            return "Could not create the artwork rendering context."
        case .encodingFailed(let name):
            return "Could not encode generated asset: \(name)"
        }
    }
}

private struct HeroArtworkGenerator {
    static let logicalSize = NSSize(width: 2_000, height: 1_000)

    let icon: RasterAsset
    let reminderOverlay: RasterAsset
    let taskPanel: RasterAsset

    init(repositoryRoot: URL) throws {
        let iconURL = repositoryRoot.appendingPathComponent("docs/assets/nudge-icon.png")
        let reminderURL = repositoryRoot.appendingPathComponent("docs/screenshots/reminder-overlay.png")
        let taskPanelURL = repositoryRoot.appendingPathComponent("docs/screenshots/task-panel.png")

        for inputURL in [iconURL, reminderURL, taskPanelURL] where !FileManager.default.fileExists(atPath: inputURL.path) {
            throw GeneratorError.missingInput(inputURL.lastPathComponent)
        }

        icon = try RasterAsset(url: iconURL, expectedPixelSize: NSSize(width: 256, height: 256))
        reminderOverlay = try RasterAsset(url: reminderURL, expectedPixelSize: NSSize(width: 1_640, height: 540))
        taskPanel = try RasterAsset(url: taskPanelURL, expectedPixelSize: NSSize(width: 932, height: 1_080))
    }

    func render(pixelWidth: Int, pixelHeight: Int) throws -> NSBitmapImageRep {
        guard pixelWidth > 0, pixelHeight > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw GeneratorError.contextCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high

        let scaleX = CGFloat(pixelWidth) / Self.logicalSize.width
        let scaleY = CGFloat(pixelHeight) / Self.logicalSize.height
        graphicsContext.cgContext.scaleBy(x: scaleX, y: scaleY)
        drawScene(in: graphicsContext.cgContext)
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    private func drawScene(in context: CGContext) {
        let canvas = NSRect(origin: .zero, size: Self.logicalSize)
        drawBackground(in: context, canvas: canvas)
        drawInterfaceStage()
        drawBrandAndCopy()
        drawProductSurfaces()
        drawEdgeTreatment(in: context, canvas: canvas)
    }

    private func drawBackground(in context: CGContext, canvas: NSRect) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let backgroundGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                color(0x071327).cgColor,
                color(0x0A2348).cgColor,
                color(0x0A386A).cgColor,
            ] as CFArray,
            locations: [0, 0.56, 1]
        )
        if let backgroundGradient {
            context.drawLinearGradient(
                backgroundGradient,
                start: CGPoint(x: 0, y: canvas.midY),
                end: CGPoint(x: canvas.maxX, y: canvas.midY),
                options: []
            )
        }

        drawRadialGlow(
            in: context,
            center: CGPoint(x: 1_670, y: 610),
            radius: 690,
            color: color(0x3187E8, alpha: 0.28)
        )
        drawRadialGlow(
            in: context,
            center: CGPoint(x: 1_140, y: 160),
            radius: 520,
            color: color(0xEC6A59, alpha: 0.12)
        )
        drawRadialGlow(
            in: context,
            center: CGPoint(x: 1_920, y: 160),
            radius: 430,
            color: color(0xF5B54A, alpha: 0.10)
        )

        context.saveGState()
        context.setStrokeColor(color(0xD7E9FF, alpha: 0.055).cgColor)
        context.setLineWidth(1)
        for x in stride(from: CGFloat(720), through: CGFloat(2_000), by: 80) {
            context.move(to: CGPoint(x: x, y: 60))
            context.addLine(to: CGPoint(x: x, y: 940))
        }
        for y in stride(from: CGFloat(60), through: CGFloat(940), by: 80) {
            context.move(to: CGPoint(x: 720, y: y))
            context.addLine(to: CGPoint(x: 2_000, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawInterfaceStage() {
        let frame = NSRect(x: 700, y: 60, width: 1_230, height: 880)
        let framePath = NSBezierPath(roundedRect: frame, xRadius: 58, yRadius: 58)
        color(0xD9ECFF, alpha: 0.035).setFill()
        framePath.fill()
        color(0xCFE6FF, alpha: 0.10).setStroke()
        framePath.lineWidth = 1.5
        framePath.stroke()

        let upperHighlight = NSBezierPath()
        upperHighlight.move(to: NSPoint(x: frame.minX + 70, y: frame.maxY - 1))
        upperHighlight.line(to: NSPoint(x: frame.maxX - 70, y: frame.maxY - 1))
        color(0xFFFFFF, alpha: 0.10).setStroke()
        upperHighlight.lineWidth = 1
        upperHighlight.stroke()
    }

    private func drawBrandAndCopy() {
        let iconRect = NSRect(x: 104, y: 786, width: 108, height: 108)
        icon.image.draw(
            in: iconRect,
            from: NSRect(origin: .zero, size: icon.pixelSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        drawText(
            "Nudge",
            at: NSPoint(x: 236, y: 817),
            font: .systemFont(ofSize: 43, weight: .semibold),
            color: color(0xFFFFFF, alpha: 0.96)
        )
        drawText(
            "NATIVE macOS REMINDERS",
            at: NSPoint(x: 108, y: 733),
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: color(0x8FC4FF, alpha: 0.92),
            kern: 2.4
        )

        drawText(
            "Your calendar,",
            at: NSPoint(x: 102, y: 570),
            font: .systemFont(ofSize: 78, weight: .bold),
            color: color(0xFFFFFF)
        )
        drawText(
            "impossible",
            at: NSPoint(x: 102, y: 480),
            font: .systemFont(ofSize: 78, weight: .bold),
            color: color(0xFFFFFF)
        )
        drawText(
            "to ignore.",
            at: NSPoint(x: 102, y: 390),
            font: .systemFont(ofSize: 78, weight: .bold),
            color: color(0xF08A63)
        )

        drawText(
            "On-screen Google Calendar reminders",
            at: NSPoint(x: 108, y: 303),
            font: .systemFont(ofSize: 28, weight: .regular),
            color: color(0xD4E2F3, alpha: 0.88)
        )
        drawText(
            "and Google Tasks that stay within reach.",
            at: NSPoint(x: 108, y: 261),
            font: .systemFont(ofSize: 28, weight: .regular),
            color: color(0xD4E2F3, alpha: 0.88)
        )

        let accent = NSBezierPath(roundedRect: NSRect(x: 108, y: 210, width: 92, height: 6), xRadius: 3, yRadius: 3)
        color(0xF0A34A, alpha: 0.95).setFill()
        accent.fill()
    }

    private func drawProductSurfaces() {
        let taskDestination = NSRect(x: 1_368, y: 104, width: 590, height: 720)
        let taskSource = NSRect(x: 130, y: 130, width: 672, height: 820)
        drawCroppedImage(
            taskPanel.image,
            sourceRect: taskSource,
            destinationRect: taskDestination,
            cornerRadius: 40,
            shadowBlur: 48,
            shadowOffset: NSSize(width: 0, height: -18),
            shadowAlpha: 0.44
        )

        let reminderDestination = NSRect(x: 604, y: 150, width: 1_080, height: 231)
        let reminderSource = NSRect(x: 120, y: 120, width: 1_400, height: 300)
        drawCroppedImage(
            reminderOverlay.image,
            sourceRect: reminderSource,
            destinationRect: reminderDestination,
            cornerRadius: 27,
            shadowBlur: 42,
            shadowOffset: NSSize(width: 0, height: -15),
            shadowAlpha: 0.48
        )
    }

    private func drawCroppedImage(
        _ image: NSImage,
        sourceRect: NSRect,
        destinationRect: NSRect,
        cornerRadius: CGFloat,
        shadowBlur: CGFloat,
        shadowOffset: NSSize,
        shadowAlpha: CGFloat
    ) {
        let shape = NSBezierPath(roundedRect: destinationRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x000000, alpha: shadowAlpha)
        shadow.shadowBlurRadius = shadowBlur
        shadow.shadowOffset = shadowOffset
        shadow.set()
        color(0x000000, alpha: 0.18).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        image.draw(
            in: destinationRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        color(0xFFFFFF, alpha: 0.18).setStroke()
        shape.lineWidth = 1.25
        shape.stroke()
    }

    private func drawEdgeTreatment(in context: CGContext, canvas: NSRect) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let vignette = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                color(0x000000, alpha: 0).cgColor,
                color(0x000000, alpha: 0.24).cgColor,
            ] as CFArray,
            locations: [0.68, 1]
        )
        if let vignette {
            context.drawRadialGradient(
                vignette,
                startCenter: CGPoint(x: canvas.midX, y: canvas.midY),
                startRadius: 0,
                endCenter: CGPoint(x: canvas.midX, y: canvas.midY),
                endRadius: 1_160,
                options: [.drawsAfterEndLocation]
            )
        }
    }

    private func drawRadialGlow(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color glowColor: NSColor
    ) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [glowColor.cgColor, glowColor.withAlphaComponent(0).cgColor] as CFArray,
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

    private func drawText(
        _ text: String,
        at point: NSPoint,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        (text as NSString).draw(
            at: point,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .kern: kern,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func color(_ hexadecimal: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            deviceRed: CGFloat((hexadecimal >> 16) & 0xFF) / 255,
            green: CGFloat((hexadecimal >> 8) & 0xFF) / 255,
            blue: CGFloat(hexadecimal & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw GeneratorError.encodingFailed(url.lastPathComponent)
    }
    try data.write(to: url, options: .atomic)
}

private func writeJPEG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(
        using: .jpeg,
        properties: [.compressionFactor: 0.92]
    ) else {
        throw GeneratorError.encodingFailed(url.lastPathComponent)
    }
    try data.write(to: url, options: .atomic)
}

private func generateAssets(repositoryRoot: URL) throws {
    let outputDirectory = repositoryRoot.appendingPathComponent("docs/assets")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let generator = try HeroArtworkGenerator(repositoryRoot: repositoryRoot)
    let hero = try generator.render(pixelWidth: 2_000, pixelHeight: 1_000)
    let socialPreview = try generator.render(pixelWidth: 1_280, pixelHeight: 640)

    try writePNG(hero, to: outputDirectory.appendingPathComponent("nudge-hero.png"))
    try writeJPEG(socialPreview, to: outputDirectory.appendingPathComponent("nudge-social-preview.jpg"))
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 2 else {
        FileHandle.standardError.write(Data("usage: generate_readme_assets <repository-root>\n".utf8))
        exit(2)
    }

    let repositoryRoot = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    try generateAssets(repositoryRoot: repositoryRoot)
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("README asset generation failed: \(message)\n".utf8))
    exit(1)
}
