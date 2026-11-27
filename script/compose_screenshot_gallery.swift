import AppKit
import Foundation

private enum ScreenshotPage: String, CaseIterable {
    case menu = "menu-bar.png"
    case overlay = "reminder-overlay.png"
    case account = "settings-account.png"
    case application = "settings-application.png"
    case reminders = "settings-reminders.png"
    case tasks = "settings-tasks.png"
    case bird = "settings-bird.png"
    case taskPanel = "task-panel.png"

    var canvasSize: NSSize {
        switch self {
        case .menu:
            return NSSize(width: 1_320, height: 1_380)
        case .overlay:
            return NSSize(width: 1_640, height: 440)
        case .account, .application, .reminders, .tasks, .bird:
            return NSSize(width: 1_440, height: 1_560)
        case .taskPanel:
            return NSSize(width: 932, height: 1_080)
        }
    }

    /// Where the trimmed capture is centred. Captures are never scaled up.
    var contentBounds: NSRect {
        switch self {
        case .menu:
            return NSRect(x: 60, y: 60, width: 1_200, height: 1_160)
        case .overlay:
            return NSRect(x: 100, y: 100, width: 1_440, height: 240)
        case .account, .application, .reminders, .tasks, .bird:
            return NSRect(x: 80, y: 28, width: 1_280, height: 1_504)
        case .taskPanel:
            return NSRect(x: 60, y: 60, width: 812, height: 960)
        }
    }

    /// Borderless surfaces without a window shadow of their own get a soft drop shadow.
    var addsDropShadow: Bool {
        switch self {
        case .menu, .overlay:
            return true
        case .account, .application, .reminders, .tasks, .bird, .taskPanel:
            return false
        }
    }
}

private enum ComposerError: LocalizedError {
    case usage
    case unreadableMenuBarIcon
    case contextCreationFailed
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: compose_screenshot_gallery <raw-directory> <output-directory> <menu-bar-icon.svg>"
        case .unreadableMenuBarIcon:
            return "The menu-bar icon could not be loaded."
        case .contextCreationFailed:
            return "Could not create the screenshot artwork context."
        case .encodingFailed(let name):
            return "Could not encode composed screenshot: \(name)"
        }
    }
}

private struct ScreenshotGalleryComposer {
    let rawDirectory: URL
    let outputDirectory: URL
    let menuBarIcon: NSImage

    func compose() throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        for page in ScreenshotPage.allCases {
            let capture = try NudgeTrimmedCapture(
                url: rawDirectory.appendingPathComponent(page.rawValue)
            )
            let bitmap = try render(page: page, capture: capture)
            let outputURL = outputDirectory.appendingPathComponent(page.rawValue)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw ComposerError.encodingFailed(page.rawValue)
            }
            try data.write(to: outputURL, options: .atomic)
        }
    }

    private func render(page: ScreenshotPage, capture: NudgeTrimmedCapture) throws -> NSBitmapImageRep {
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
        graphicsContext.imageInterpolation = .high
        let canvas = NSRect(origin: .zero, size: page.canvasSize)
        NudgeArtworkBackground.drawGallery(in: graphicsContext.cgContext, canvas: canvas)

        var bounds = page.contentBounds
        if page == .menu {
            let bar = drawMenuBar(in: canvas)
            bounds.size.height = bar.minY - 14 - bounds.minY
        }
        var destination = capture.fittedRect(in: bounds)
        if page == .menu {
            // A status-item menu hangs from the menu bar rather than floating in the middle.
            destination.origin.y = bounds.maxY - destination.height
        }
        draw(capture: capture, in: destination, addsDropShadow: page.addsDropShadow)

        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func draw(capture: NudgeTrimmedCapture, in destination: NSRect, addsDropShadow: Bool) {
        NSGraphicsContext.saveGraphicsState()
        if addsDropShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NudgeArtworkPalette.color(NudgeArtworkPalette.ink, alpha: 0.26)
            shadow.shadowBlurRadius = 36
            shadow.shadowOffset = NSSize(width: 0, height: -14)
            shadow.set()
        }
        capture.draw(in: destination)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Fictional menu-bar strip: the Nudge status item (highlighted, as while its menu is
    /// open) plus generic system glyphs and a fixed clock.
    private func drawMenuBar(in canvas: NSRect) -> NSRect {
        let bar = NSRect(x: 34, y: canvas.height - 96, width: canvas.width - 68, height: 60)
        let barPath = NudgeInk.unevenRoundedRect(
            bar, topLeft: 20, topRight: 18, bottomRight: 21, bottomLeft: 17
        )
        NudgeInk.drawSticker(
            barPath,
            fill: NudgeArtworkPalette.color(0xFFFFFF),
            lineWidth: 3,
            shadowOffset: NSSize(width: 0, height: -5)
        )

        let ink = NudgeArtworkPalette.color(NudgeArtworkPalette.ink)
        let highlight = NSRect(x: 84, y: bar.minY + 9, width: 64, height: 42)
        NudgeArtworkPalette.color(NudgeArtworkPalette.blue, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 11, yRadius: 11).fill()
        tinted(menuBarIcon, color: ink).draw(
            in: NSRect(x: highlight.midX - 17, y: highlight.midY - 17, width: 34, height: 34)
        )

        drawSymbol("wifi", in: NSRect(x: bar.maxX - 262, y: bar.minY + 16, width: 30, height: 28))
        drawSymbol("battery.100", in: NSRect(x: bar.maxX - 210, y: bar.minY + 15, width: 40, height: 30))
        ("9:41" as NSString).draw(
            at: NSPoint(x: bar.maxX - 140, y: bar.minY + 16),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: ink,
            ]
        )
        return bar
    }

    private func drawSymbol(_ name: String, in rect: NSRect) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: rect.height * 0.72,
            weight: .semibold
        )
        let configured = image.withSymbolConfiguration(configuration) ?? image
        tinted(configured, color: NudgeArtworkPalette.color(NudgeArtworkPalette.ink))
            .draw(in: rect)
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

@main
private enum ComposeScreenshotGallery {
    static func main() {
        do {
            guard CommandLine.arguments.count == 4 else {
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
            guard let menuBarIcon = NSImage(
                contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])
            ) else {
                throw ComposerError.unreadableMenuBarIcon
            }
            try ScreenshotGalleryComposer(
                rawDirectory: rawDirectory,
                outputDirectory: outputDirectory,
                menuBarIcon: menuBarIcon
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
