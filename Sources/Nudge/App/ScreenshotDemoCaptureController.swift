#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class ScreenshotDemoCaptureController {
    private let configuration: ScreenshotDemoConfiguration
    private let calendarCoordinator: CalendarScheduleCoordinator
    private let googleTasksCoordinator: GoogleTasksSyncCoordinator
    private let googleOAuthConfigurationManager: GoogleOAuthClientConfigurationManager
    private let windowCoordinator: WindowPresentationCoordinator
    private let launchAtLoginManager: LaunchAtLoginManager
    private let repositoryContainer: LocalRepositoryContainer
    private var captureWindow: NSWindow?

    init(
        configuration: ScreenshotDemoConfiguration,
        calendarCoordinator: CalendarScheduleCoordinator,
        googleTasksCoordinator: GoogleTasksSyncCoordinator,
        googleOAuthConfigurationManager: GoogleOAuthClientConfigurationManager,
        windowCoordinator: WindowPresentationCoordinator,
        launchAtLoginManager: LaunchAtLoginManager,
        repositoryContainer: LocalRepositoryContainer
    ) {
        self.configuration = configuration
        self.calendarCoordinator = calendarCoordinator
        self.googleTasksCoordinator = googleTasksCoordinator
        self.googleOAuthConfigurationManager = googleOAuthConfigurationManager
        self.windowCoordinator = windowCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.repositoryContainer = repositoryContainer
    }

    func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await calendarCoordinator.restoreAtLaunch()
            windowCoordinator.reloadTaskPanelCache()
            do {
                try await renderScreenshot()
            } catch {
                let message = "Nudge screenshot capture failed: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
            calendarCoordinator.stop()
            googleTasksCoordinator.stop()
            captureWindow?.orderOut(nil)
            captureWindow = nil
            NSApplication.shared.terminate(nil)
        }
    }

    private func renderScreenshot() async throws {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        let output = makeOutput(for: configuration.page)
        let hostingView = NSHostingView(rootView: output.view)
        hostingView.frame = CGRect(origin: .zero, size: output.size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hostingView
        window.setFrameOrigin(CGPoint(x: 80, y: 80))
        captureWindow = window
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(output.size.width * 2),
            pixelsHigh: Int(output.size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CaptureError.couldNotCreateBitmap
        }
        bitmap.size = output.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(
            using: .png,
            properties: [.compressionFactor: 1]
        ) else {
            throw CaptureError.couldNotEncodePNG
        }
        try FileManager.default.createDirectory(
            at: configuration.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: configuration.outputURL, options: .atomic)
    }

    private func makeOutput(for page: ScreenshotDemoPage) -> (
        view: AnyView,
        size: CGSize
    ) {
        switch page {
        case .menu:
            return canvas(
                content: AnyView(ScreenshotDemoMenuView()),
                contentSize: CGSize(width: 368, height: 486),
                canvasSize: CGSize(width: 448, height: 566)
            )
        case .account, .reminders, .tasks, .application:
            let tab: SettingsTab
            switch page {
            case .account: tab = .account
            case .reminders: tab = .reminders
            case .tasks: tab = .tasks
            case .application: tab = .application
            default: tab = .account
            }
            let settings = SettingsView(
                calendarCoordinator: calendarCoordinator,
                googleTasksCoordinator: googleTasksCoordinator,
                googleOAuthConfigurationManager: googleOAuthConfigurationManager,
                windowCoordinator: windowCoordinator,
                launchAtLoginManager: launchAtLoginManager,
                persistenceStatusMessage: nil,
                initialTab: tab
            )
            return canvas(
                content: AnyView(settings),
                contentSize: CGSize(width: 640, height: 700),
                canvasSize: CGSize(width: 720, height: 780),
                cornerRadius: 18
            )
        case .overlay:
            let store = ReminderOverlayStore()
            store.present(
                ScreenshotDemoDependencies.reminderFixture(),
                now: ScreenshotDemoDependencies.referenceDate
            )
            let overlay = ReminderOverlayView(
                store: store,
                onDismiss: {},
                onSnooze: {},
                onOpen: {}
            )
            return canvas(
                content: AnyView(overlay.frame(width: 700, height: 150)),
                contentSize: CGSize(width: 700, height: 150),
                canvasSize: CGSize(width: 820, height: 270),
                cornerRadius: 0,
                addsSurfaceShadow: false
            )
        case .taskPanel:
            let store = TaskPanelStore(
                taskRepository: repositoryContainer.taskRepository,
                stateRepository: repositoryContainer.taskPanelStateRepository,
                syncMetadataRepository: repositoryContainer.syncMetadataRepository
            )
            let panel = TaskPanelView(
                store: store,
                onHide: {},
                onToggleDisplayMode: {},
                onResizeBegan: { _ in },
                onResizeChanged: { _ in },
                onResizeEnded: {}
            )
            .frame(width: 346, height: 420)
            return canvas(
                content: AnyView(panel),
                contentSize: CGSize(width: 346, height: 420),
                canvasSize: CGSize(width: 466, height: 540),
                cornerRadius: 0,
                addsSurfaceShadow: false
            )
        }
    }

    private func canvas(
        content: AnyView,
        contentSize: CGSize,
        canvasSize: CGSize,
        cornerRadius: CGFloat = 14,
        addsSurfaceShadow: Bool = true
    ) -> (view: AnyView, size: CGSize) {
        let view = ScreenshotDemoCanvasView(
            content: content,
            contentSize: contentSize,
            canvasSize: canvasSize,
            cornerRadius: cornerRadius,
            addsSurfaceShadow: addsSurfaceShadow
        )
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.calendar, Calendar(identifier: .gregorian))
        return (AnyView(view), canvasSize)
    }
}

private extension ScreenshotDemoCaptureController {
    enum CaptureError: Error {
        case couldNotCreateBitmap
        case couldNotEncodePNG
    }
}

private struct ScreenshotDemoCanvasView: View {
    let content: AnyView
    let contentSize: CGSize
    let canvasSize: CGSize
    let cornerRadius: CGFloat
    let addsSurfaceShadow: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.965, green: 0.974, blue: 0.986),
                    Color(red: 0.895, green: 0.925, blue: 0.957),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            content
                .frame(width: contentSize.width, height: contentSize.height)
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(
                    color: addsSurfaceShadow ? .black.opacity(0.20) : .clear,
                    radius: 18,
                    x: 0,
                    y: 10
                )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

private struct ScreenshotDemoMenuView: View {
    var body: some View {
        VStack(spacing: 0) {
            menuRow("Show Test Reminder")
            divider
            menuRow("Show Task Panel")
            menuRow("Hide Task Panel")
            menuRow("Task Panel Corner", trailing: "›")
            menuRow("Reset Task Panel Position")
            menuRow("Allow Reminder Over Full-Screen Apps")
            menuRow("Allow Task Panel Over Full-Screen Apps")
            menuRow("Refresh Tasks")
            divider
            menuRow("Settings…")
            menuRow("Quit Nudge", trailing: "⌘Q")
        }
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.7), lineWidth: 1)
        }
    }

    private func menuRow(_ title: String, trailing: String? = nil) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private var divider: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}
#endif
