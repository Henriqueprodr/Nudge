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
    let handMark: NSImage
    let reminderOverlay: NudgeTrimmedCapture
    let taskPanel: NudgeTrimmedCapture

    /// The hero uses the transparent native captures staged by `capture_screenshots.sh`, so
    /// the product surfaces sit directly on the artwork instead of on a gallery background.
    init(repositoryRoot: URL) throws {
        let iconURL = repositoryRoot.appendingPathComponent("docs/assets/nudge-icon.png")
        let rawDirectory = repositoryRoot.appendingPathComponent(".build/screenshots/raw")
        let reminderURL = rawDirectory.appendingPathComponent("reminder-overlay.png")
        let taskPanelURL = rawDirectory.appendingPathComponent("task-panel.png")
        let handMarkURL = repositoryRoot.appendingPathComponent(
            "Sources/Nudge/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg"
        )

        for inputURL in [iconURL, reminderURL, taskPanelURL, handMarkURL] where !FileManager.default.fileExists(atPath: inputURL.path) {
            throw GeneratorError.missingInput(inputURL.lastPathComponent)
        }

        icon = try RasterAsset(url: iconURL, expectedPixelSize: NSSize(width: 256, height: 256))
        guard let handMark = NSImage(contentsOf: handMarkURL) else {
            throw GeneratorError.unreadableImage(handMarkURL.lastPathComponent)
        }
        self.handMark = handMark
        reminderOverlay = try NudgeTrimmedCapture(url: reminderURL)
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
        let frame = NSRect(x: 880, y: 78, width: 1_040, height: 846)
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
        let handRect = NSRect(x: 900, y: 372, width: 420, height: 420)
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
        let iconRect = NSRect(x: 92, y: 772, width: 132, height: 132)
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
        drawText("On-screen Google Calendar reminders", at: NSPoint(x: 108, y: 272), font: bodyFont, color: body)
        drawText("and Google Tasks that stay within reach.", at: NSPoint(x: 108, y: 230), font: bodyFont, color: body)
    }

    private func drawProductSurfaces() {
        let taskBounds = NSRect(x: 1_330, y: 150, width: 560, height: 740)
        drawCapture(taskPanel, in: taskPanel.fittedRect(in: taskBounds), dropShadow: false)

        let reminderBounds = NSRect(x: 640, y: 120, width: 1_120, height: 190)
        drawCapture(
            reminderOverlay,
            in: reminderOverlay.fittedRect(in: reminderBounds),
            dropShadow: true
        )
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
