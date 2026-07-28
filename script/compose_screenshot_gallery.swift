import AppKit
import Foundation

private enum ScreenshotPage: String, CaseIterable {
    case menu = "menu-bar.png"
    case overlay = "reminder-overlay.png"
    case account = "settings-account.png"
    case application = "settings-application.png"
    case reminders = "settings-reminders.png"
    case tasks = "settings-tasks.png"
    case taskPanel = "task-panel.png"

    var canvasSize: NSSize {
        switch self {
        case .menu:
            return NSSize(width: 896, height: 1_132)
        case .overlay:
            return NSSize(width: 1_640, height: 540)
        case .account, .application, .reminders, .tasks:
            return NSSize(width: 1_440, height: 1_560)
        case .taskPanel:
            return NSSize(width: 932, height: 1_080)
        }
    }

    var contentBounds: NSRect {
        switch self {
        case .menu:
            return NSRect(x: 80, y: 70, width: 736, height: 930)
        case .overlay:
            return NSRect(x: 120, y: 120, width: 1_400, height: 300)
        case .account, .application, .reminders, .tasks:
            return NSRect(x: 80, y: 48, width: 1_280, height: 1_464)
        case .taskPanel:
            return NSRect(x: 120, y: 120, width: 692, height: 840)
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .menu:
            return 24
        case .overlay:
            return 22
        case .account, .application, .reminders, .tasks:
            return 28
        case .taskPanel:
            return 40
        }
    }
}

private enum ComposerError: LocalizedError {
    case usage
    case missingInput(String)
    case unreadableInput(String)
    case contextCreationFailed
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: compose_screenshot_gallery <raw-directory> <output-directory>"
        case .missingInput(let name):
            return "Required native capture is missing: \(name)"
        case .unreadableInput(let name):
            return "Native capture is not a readable PNG: \(name)"
        case .contextCreationFailed:
            return "Could not create the screenshot artwork context."
        case .encodingFailed(let name):
            return "Could not encode composed screenshot: \(name)"
        }
    }
}

private struct RasterImage {
    let image: NSImage
    let size: NSSize

    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComposerError.missingInput(url.lastPathComponent)
        }
        guard let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data)
        else {
            throw ComposerError.unreadableInput(url.lastPathComponent)
        }
        size = NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        self.image = image
    }
}

private struct ScreenshotGalleryComposer {
    let rawDirectory: URL
    let outputDirectory: URL

    func compose() throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        for page in ScreenshotPage.allCases {
            let inputURL = rawDirectory.appendingPathComponent(page.rawValue)
            let raster = try RasterImage(url: inputURL)
            let bitmap = try render(page: page, raster: raster)
            let outputURL = outputDirectory.appendingPathComponent(page.rawValue)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw ComposerError.encodingFailed(page.rawValue)
            }
            try data.write(to: outputURL, options: .atomic)
        }
    }

    private func render(page: ScreenshotPage, raster: RasterImage) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(page.canvasSize.width),
            pixelsHigh: Int(page.canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ComposerError.contextCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = NSImageInterpolation.high
        let canvas = NSRect(origin: .zero, size: page.canvasSize)
        NudgeArtworkBackground.drawGallery(in: graphicsContext.cgContext, canvas: canvas)
        if page == .menu {
            drawMenuBar(in: canvas)
        }
        draw(raster: raster, in: page.contentBounds, cornerRadius: page.cornerRadius)
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func draw(raster: RasterImage, in bounds: NSRect, cornerRadius: CGFloat) {
        let scale = min(bounds.width / raster.size.width, bounds.height / raster.size.height)
        let destinationSize = NSSize(
            width: raster.size.width * scale,
            height: raster.size.height * scale
        )
        let destination = NSRect(
            x: bounds.midX - destinationSize.width / 2,
            y: bounds.midY - destinationSize.height / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )
        let shape = NSBezierPath(
            roundedRect: destination,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NudgeArtworkPalette.color(0x000000, alpha: 0.48)
        shadow.shadowBlurRadius = 42
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        NudgeArtworkPalette.color(0x000000, alpha: 0.16).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        raster.image.draw(
            in: destination,
            from: NSRect(origin: .zero, size: raster.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMenuBar(in canvas: NSRect) {
        let bar = NSRect(x: 34, y: canvas.height - 92, width: canvas.width - 68, height: 58)
        let path = NSBezierPath(roundedRect: bar, xRadius: 19, yRadius: 19)
        NudgeArtworkPalette.color(0xFFFFFF, alpha: 0.88).setFill()
        path.fill()
        NudgeArtworkPalette.color(0xFFFFFF, alpha: 0.40).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawSymbol("bell.badge.fill", in: NSRect(x: 566, y: bar.minY + 15, width: 28, height: 28))
        drawSymbol("wifi", in: NSRect(x: 626, y: bar.minY + 15, width: 28, height: 28))
        drawSymbol("battery.100", in: NSRect(x: 680, y: bar.minY + 14, width: 36, height: 30))
        ("9:41" as NSString).draw(
            at: NSPoint(x: 748, y: bar.minY + 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 21, weight: .medium),
                .foregroundColor: NudgeArtworkPalette.color(0x10151C, alpha: 0.90),
            ]
        )
    }

    private func drawSymbol(_ name: String, in rect: NSRect) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: rect.height * 0.72,
            weight: .medium
        )
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.draw(in: rect)
    }
}

@main
private enum ComposeScreenshotGallery {
    static func main() {
        do {
            guard CommandLine.arguments.count == 3 else {
                throw ComposerError.usage
            }
            let rawDirectory = URL(
                fileURLWithPath: CommandLine.arguments[1],
                isDirectory: true
            ).standardizedFileURL
            let outputDirectory = URL(
                fileURLWithPath: CommandLine.arguments[2],
                isDirectory: true
            ).standardizedFileURL
            try ScreenshotGalleryComposer(
                rawDirectory: rawDirectory,
                outputDirectory: outputDirectory
            ).compose()
        } catch {
            let description = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            FileHandle.standardError.write(
                Data("Screenshot composition failed: \(description)\n".utf8)
            )
            exit(1)
        }
    }
}
