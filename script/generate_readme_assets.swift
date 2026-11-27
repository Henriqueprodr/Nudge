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

/// Frames the full-bleed Icon Composer export the way macOS shows app icons: the rounded
/// square inset on a transparent canvas with a soft shadow beneath it.
private enum ReadmeIconRenderer {
    static let pixelSize: CGFloat = 1_024
    /// macOS app icons occupy 824 of 1024 points, centred.
    static let bodySize: CGFloat = 824

    static func render(exportURL: URL) throws -> NSBitmapImageRep {
        guard FileManager.default.fileExists(atPath: exportURL.path) else {
            throw GeneratorError.missingInput(exportURL.lastPathComponent)
        }
        guard let data = try? Data(contentsOf: exportURL),
              let representation = NSBitmapImageRep(data: data)
        else {
            throw GeneratorError.unreadableImage(exportURL.lastPathComponent)
        }
        let exported = NSImage(
            size: NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        )
        exported.addRepresentation(representation)

        let size = Int(pixelSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw GeneratorError.contextCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        let inset = (pixelSize - bodySize) / 2
        let body = NSRect(x: inset, y: inset + 8, width: bodySize, height: bodySize)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(deviceWhite: 0, alpha: 0.30)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        exported.draw(
            in: body,
            from: NSRect(origin: .zero, size: exported.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}

private struct HeroArtworkGenerator {
    static let logicalSize = NSSize(width: 2_000, height: 1_000)

    let icon: RasterAsset
    let handMark: NSImage
    let birdAlert: NudgeTrimmedCapture
    let taskNag: NudgeTrimmedCapture
    let taskPanel: NudgeTrimmedCapture

    /// The hero uses the transparent native captures staged by `capture_screenshots.sh`, so
    /// the product surfaces sit directly on the artwork instead of on a gallery background.
    init(repositoryRoot: URL) throws {
        let iconURL = repositoryRoot.appendingPathComponent("docs/assets/nudge-icon.png")
        let rawDirectory = repositoryRoot.appendingPathComponent(".build/screenshots/raw")
        let birdAlertURL = rawDirectory.appendingPathComponent("bird-alert.png")
        let taskNagURL = rawDirectory.appendingPathComponent("task-nag.png")
        let taskPanelURL = rawDirectory.appendingPathComponent("task-panel.png")
        let handMarkURL = repositoryRoot.appendingPathComponent(
            "Sources/Nudge/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg"
        )

        for inputURL in [iconURL, birdAlertURL, taskNagURL, taskPanelURL, handMarkURL] where !FileManager.default.fileExists(atPath: inputURL.path) {
            throw GeneratorError.missingInput(inputURL.lastPathComponent)
        }

        icon = try RasterAsset(
            url: iconURL,
            expectedPixelSize: NSSize(width: ReadmeIconRenderer.pixelSize, height: ReadmeIconRenderer.pixelSize)
        )
        guard let handMark = NSImage(contentsOf: handMarkURL) else {
            throw GeneratorError.unreadableImage(handMarkURL.lastPathComponent)
        }
        self.handMark = handMark
        birdAlert = try NudgeTrimmedCapture(url: birdAlertURL)
        taskNag = try NudgeTrimmedCapture(url: taskNagURL)
        taskPanel = try NudgeTrimmedCapture(url: taskPanelURL)
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
        NudgeArtworkBackground.drawHero(in: context, canvas: canvas)
        drawInterfaceStage(in: context)
        drawBrandAndCopy()
        drawProductSurfaces()
    }

    /// A blue sticker card, outlined in ink like the app's surfaces, behind the product UI.
    private func drawInterfaceStage(in context: CGContext) {
        let frame = NSRect(x: 900, y: 214, width: 1_020, height: 710)
        let path = NudgeInk.unevenRoundedRect(
            frame, topLeft: 64, topRight: 56, bottomRight: 68, bottomLeft: 58
        )
        NudgeInk.drawSticker(
            path,
            fill: color(NudgeArtworkPalette.blue),
            lineWidth: 6,
            shadowOffset: NSSize(width: 14, height: -14)
        )

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        context.setStrokeColor(color(0xFFFFFF, alpha: 0.13).cgColor)
        context.setLineWidth(1.5)
        for x in stride(from: frame.minX + 20, through: frame.maxX, by: 40) {
            context.move(to: CGPoint(x: x, y: frame.minY))
            context.addLine(to: CGPoint(x: x, y: frame.maxY))
        }
        for y in stride(from: frame.minY + 20, through: frame.maxY, by: 40) {
            context.move(to: CGPoint(x: frame.minX, y: y))
            context.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        context.strokePath()
        NSGraphicsContext.restoreGraphicsState()

        // The logo's tapping hand, in paper white, fills the stage beside the Tasks panel.
        let handRect = NSRect(x: 960, y: 440, width: 400, height: 400)
        let whiteHand = NSImage(size: handRect.size, flipped: false) { [handMark] rect in
            handMark.draw(in: rect)
            NudgeArtworkPalette.color(NudgeArtworkPalette.paper).setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        whiteHand.draw(in: handRect)
    }

    private func drawBrandAndCopy() {
        let ink = color(NudgeArtworkPalette.ink)
        let iconRect = NSRect(x: 84, y: 760, width: 156, height: 156)
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
            at: NSPoint(x: 236, y: 812),
            font: .systemFont(ofSize: 48, weight: .bold),
            color: ink
        )
        drawText(
            "NATIVE macOS REMINDERS",
            at: NSPoint(x: 108, y: 718),
            font: .systemFont(ofSize: 19, weight: .heavy),
            color: color(NudgeArtworkPalette.blue),
            kern: 2.6
        )

        let headlineFont = NSFont.systemFont(ofSize: 80, weight: .heavy)
        drawText("Your calendar,", at: NSPoint(x: 102, y: 560), font: headlineFont, color: ink)
        drawText("impossible", at: NSPoint(x: 102, y: 468), font: headlineFont, color: ink)
        let accentWidth = drawText(
            "to ignore.",
            at: NSPoint(x: 102, y: 376),
            font: headlineFont,
            color: color(NudgeArtworkPalette.blue)
        )

        let underline = NudgeInk.wavyLine(
            fromX: 110,
            toX: 102 + accentWidth - 18,
            y: 366,
            amplitude: 4.5,
            wavelength: 42
        )
        color(NudgeArtworkPalette.green).setStroke()
        underline.lineWidth = 8
        underline.stroke()

        let body = color(NudgeArtworkPalette.ink, alpha: 0.78)
        let bodyFont = NSFont.systemFont(ofSize: 29, weight: .medium)
        drawText("Google Calendar alerts that land on screen,", at: NSPoint(x: 108, y: 276), font: bodyFont, color: body)
        drawText("Google Tasks that stay in view, and a bird", at: NSPoint(x: 108, y: 234), font: bodyFont, color: body)
        drawText("that won't let you forget either.", at: NSPoint(x: 108, y: 192), font: bodyFont, color: body)
    }

    private func drawProductSurfaces() {
        // The two alerts share one scale so they read as the same screen.
        let scale: CGFloat = 0.55
        // The Tasks panel is its own corner window, so it may sit a touch larger.
        let panel = scaled(taskPanel, by: 0.62, topRight: NSPoint(x: 1_884, y: 894))
        drawCapture(taskPanel, in: panel, dropShadow: true)

        let nag = scaled(taskNag, by: scale, topRight: NSPoint(x: 1_740, y: 384))
        drawCapture(taskNag, in: nag, dropShadow: true)

        let alert = scaled(birdAlert, by: scale, topRight: NSPoint(x: 1_880, y: 262))
        drawCapture(birdAlert, in: alert, dropShadow: true)
    }

    private func scaled(
        _ capture: NudgeTrimmedCapture,
        by scale: CGFloat,
        topRight: NSPoint
    ) -> NSRect {
        let width = (capture.size.width * scale).rounded()
        let height = (capture.size.height * scale).rounded()
        return NSRect(x: topRight.x - width, y: topRight.y - height, width: width, height: height)
    }

    private func drawCapture(_ capture: NudgeTrimmedCapture, in destination: NSRect, dropShadow: Bool) {
        NSGraphicsContext.saveGraphicsState()
        if dropShadow {
            let shadow = NSShadow()
            shadow.shadowColor = color(NudgeArtworkPalette.ink, alpha: 0.30)
            shadow.shadowBlurRadius = 34
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
        }
        capture.draw(in: destination)
        NSGraphicsContext.restoreGraphicsState()
    }

    @discardableResult
    private func drawText(
        _ text: String,
        at point: NSPoint,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0
    ) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern,
            .paragraphStyle: paragraphStyle,
        ]
        (text as NSString).draw(at: point, withAttributes: attributes)
        return (text as NSString).size(withAttributes: attributes).width
    }

    private func color(_ hexadecimal: Int, alpha: CGFloat = 1) -> NSColor {
        NudgeArtworkPalette.color(hexadecimal, alpha: alpha)
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

    let iconExportURL = repositoryRoot.appendingPathComponent(".build/readme-assets/app-icon-export.png")
    let icon = try ReadmeIconRenderer.render(exportURL: iconExportURL)
    try writePNG(icon, to: outputDirectory.appendingPathComponent("nudge-icon.png"))

    let generator = try HeroArtworkGenerator(repositoryRoot: repositoryRoot)
    let hero = try generator.render(pixelWidth: 2_000, pixelHeight: 1_000)
    let socialPreview = try generator.render(pixelWidth: 1_280, pixelHeight: 640)

    try writePNG(hero, to: outputDirectory.appendingPathComponent("nudge-hero.png"))
    try writeJPEG(socialPreview, to: outputDirectory.appendingPathComponent("nudge-social-preview.jpg"))
}

@main
private enum GenerateReadmeAssets {
    static func main() {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count == 2 else {
                FileHandle.standardError.write(
                    Data("usage: generate_readme_assets <repository-root>\n".utf8)
                )
                exit(2)
            }

            let repositoryRoot = URL(
                fileURLWithPath: arguments[1],
                isDirectory: true
            ).standardizedFileURL
            try generateAssets(repositoryRoot: repositoryRoot)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            FileHandle.standardError.write(
                Data("README asset generation failed: \(message)\n".utf8)
            )
            exit(1)
        }
    }
}
