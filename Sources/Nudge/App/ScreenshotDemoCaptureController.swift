#if DEBUG
import AppKit
import CoreGraphics
import ScreenCaptureKit
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
    private let permissionChecker: ScreenshotCapturePermissionChecking
    private var captureWindow: NSWindow?
    private var menuTarget: ScreenshotDemoMenuTarget?

    init(
        configuration: ScreenshotDemoConfiguration,
        calendarCoordinator: CalendarScheduleCoordinator,
        googleTasksCoordinator: GoogleTasksSyncCoordinator,
        googleOAuthConfigurationManager: GoogleOAuthClientConfigurationManager,
        windowCoordinator: WindowPresentationCoordinator,
        launchAtLoginManager: LaunchAtLoginManager,
        repositoryContainer: LocalRepositoryContainer,
        permissionChecker: ScreenshotCapturePermissionChecking =
            SystemScreenshotCapturePermissionChecker()
    ) {
        self.configuration = configuration
        self.calendarCoordinator = calendarCoordinator
        self.googleTasksCoordinator = googleTasksCoordinator
        self.googleOAuthConfigurationManager = googleOAuthConfigurationManager
        self.windowCoordinator = windowCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.repositoryContainer = repositoryContainer
        self.permissionChecker = permissionChecker
    }

    func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await calendarCoordinator.restoreAtLaunch()
            windowCoordinator.reloadTaskPanelCache()
            do {
                try permissionChecker.requirePermission()
                try await renderScreenshot()
            } catch {
                let description = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                let message = "Nudge screenshot capture failed: \(description)\n"
                FileHandle.standardError.write(Data(message.utf8))
                let errorURL = configuration.outputURL
                    .deletingPathExtension()
                    .appendingPathExtension("error.txt")
                try? Data(message.utf8).write(to: errorURL, options: .atomic)
            }
            calendarCoordinator.stop()
            googleTasksCoordinator.stop()
            captureWindow?.orderOut(nil)
            captureWindow = nil
            menuTarget = nil
            NSApplication.shared.terminate(nil)
        }
    }

    private func renderScreenshot() async throws {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let pngData: Data
        if configuration.page == .menu {
            pngData = try await captureNativeMenu()
        } else {
            let window = try makeWindow(for: configuration.page)
            captureWindow = window
            window.appearance = NSAppearance(named: .aqua)
            window.sharingType = .readOnly
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .seconds(1))
            window.contentView?.layoutSubtreeIfNeeded()
            pngData = try await Self.captureWindowPNG(windowNumber: window.windowNumber)
        }

        try FileManager.default.createDirectory(
            at: configuration.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: configuration.outputURL, options: .atomic)
    }

    private func makeWindow(for page: ScreenshotDemoPage) throws -> NSWindow {
        switch page {
        case .account, .reminders, .tasks, .application:
            return makeSettingsWindow(for: page)
        case .overlay:
            return makeReminderWindow()
        case .taskPanel:
            return makeTaskPanelWindow()
        case .menu:
            throw CaptureError.unsupportedPage
        }
    }

    private func makeSettingsWindow(for page: ScreenshotDemoPage) -> NSWindow {
        let tab: SettingsTab
        switch page {
        case .account:
            tab = .account
        case .reminders:
            tab = .reminders
        case .tasks:
            tab = .tasks
        case .application:
            tab = .application
        default:
            tab = .account
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
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .transaction { transaction in
            transaction.animation = nil
        }

        let hostingView = NSHostingView(rootView: settings)
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 700)
        let window = ScreenshotDemoSettingsWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nudge Settings"
        window.contentView = hostingView
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarSeparatorStyle = .automatic
        window.animationBehavior = .none
        return window
    }

    private func makeReminderWindow() -> NSWindow {
        let store = ReminderOverlayStore()
        store.present(
            ScreenshotDemoDependencies.reminderFixture(),
            now: ScreenshotDemoDependencies.referenceDate
        )
        let view = ReminderOverlayView(
            store: store,
            onDismiss: {},
            onSnooze: {},
            onOpen: {}
        )
        .environment(\.colorScheme, .light)
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .frame(width: 700, height: 150)

        let window = ReminderOverlayWindow(
            contentRect: CGRect(x: 0, y: 0, width: 700, height: 150)
        )
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private func makeTaskPanelWindow() -> NSWindow {
        let store = TaskPanelStore(
            taskRepository: repositoryContainer.taskRepository,
            stateRepository: repositoryContainer.taskPanelStateRepository,
            syncMetadataRepository: repositoryContainer.syncMetadataRepository
        )
        let view = TaskPanelView(
            store: store,
            onHide: {},
            onToggleDisplayMode: {},
            onResizeBegan: { _ in },
            onResizeChanged: { _ in },
            onResizeEnded: {},
            footerNow: ScreenshotDemoDependencies.referenceDate
        )
        .environment(\.colorScheme, .light)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .frame(width: 346, height: 420)

        let window = TaskPanelWindow(
            contentRect: CGRect(x: 0, y: 0, width: 346, height: 420)
        )
        window.contentView = NSHostingView(rootView: view)
        return window
    }

    private func captureNativeMenu() async throws -> Data {
        let knownWindowIdentifiers = try await Self.nudgeWindowIdentifiers()
        let target = ScreenshotDemoMenuTarget()
        let menu = ScreenshotDemoNativeMenu.makeMenu(target: target)
        menuTarget = target

        let anchorWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchorWindow.backgroundColor = .clear
        anchorWindow.isOpaque = false
        anchorWindow.hasShadow = false
        anchorWindow.sharingType = .none
        anchorWindow.setFrameOrigin(CGPoint(x: 300, y: 700))
        anchorWindow.orderFrontRegardless()
        captureWindow = anchorWindow

        let captureTask = Task.detached(priority: .userInitiated) {
            try await Self.captureNewMenuWindowPNG(
                excluding: knownWindowIdentifiers,
                timeout: .seconds(5)
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            menu.cancelTrackingWithoutAnimation()
        }
        menu.popUp(
            positioning: nil,
            at: CGPoint(x: 0, y: anchorWindow.frame.height),
            in: anchorWindow.contentView
        )
        anchorWindow.orderOut(nil)
        return try await captureTask.value
    }

    nonisolated private static func nudgeWindowIdentifiers() async throws -> Set<CGWindowID> {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        return Set(
            content.windows.compactMap { window in
                guard window.owningApplication?.processID == processIdentifier else {
                    return nil
                }
                return window.windowID
            }
        )
    }

    nonisolated private static func captureNewMenuWindowPNG(
        excluding knownWindowIdentifiers: Set<CGWindowID>,
        timeout: Duration
    ) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        var hasWaitedForMenuAppearance = false
        while clock.now < deadline {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let candidateWindows = content.windows
                .filter {
                    $0.owningApplication?.processID == processIdentifier
                        && !knownWindowIdentifiers.contains($0.windowID)
                        && $0.frame.width >= 200
                        && $0.frame.height >= 120
                }
                .sorted {
                    ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height)
                }
            if !candidateWindows.isEmpty, !hasWaitedForMenuAppearance {
                hasWaitedForMenuAppearance = true
                try await Task.sleep(for: .milliseconds(350))
                continue
            }
            for window in candidateWindows {
                if let data = try? await captureMenuRegionPNG(window, content: content) {
                    return data
                }
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        throw CaptureError.menuWindowUnavailable
    }

    nonisolated private static func captureMenuRegionPNG(
        _ window: SCWindow,
        content: SCShareableContent
    ) async throws -> Data {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let application = content.applications.first(where: {
            $0.processID == processIdentifier
        }), let display = content.displays.first(where: {
            $0.frame.intersects(window.frame)
        }) else {
            throw CaptureError.windowUnavailable
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 1)
        configuration.height = max(display.height, 1)
        configuration.showsCursor = false
        configuration.shouldBeOpaque = false
        configuration.scalesToFit = true

        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let croppedImage = try cropTransparentBorder(from: image)
        let bitmap = NSBitmapImageRep(cgImage: croppedImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.couldNotEncodePNG
        }
        return data
    }

    nonisolated private static func cropTransparentBorder(
        from image: CGImage
    ) throws -> CGImage {
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
            throw CaptureError.couldNotEncodePNG
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let rowOffset = y * width * 4
            for x in 0..<width where pixels[rowOffset + x * 4 + 3] > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            throw CaptureError.windowUnavailable
        }

        let padding = 8
        minX = max(minX - padding, 0)
        minY = max(minY - padding, 0)
        maxX = min(maxX + padding, width - 1)
        maxY = min(maxY + padding, height - 1)
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        guard let cropped = image.cropping(to: cropRect) else {
            throw CaptureError.couldNotEncodePNG
        }
        return cropped
    }

    nonisolated private static func captureWindowPNG(windowNumber: Int) async throws -> Data {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            if let window = content.windows.first(where: {
                $0.windowID == CGWindowID(windowNumber)
            }), let data = try? await captureWindowPNG(window) {
                return data
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        throw CaptureError.windowUnavailable
    }

    nonisolated private static func captureWindowPNG(_ window: SCWindow) async throws -> Data {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width * 2), 1)
        configuration.height = max(Int(window.frame.height * 2), 1)
        configuration.showsCursor = false
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = false
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.scalesToFit = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.couldNotEncodePNG
        }
        return data
    }
}

protocol ScreenshotCapturePermissionChecking: Sendable {
    func requirePermission() throws
}

struct SystemScreenshotCapturePermissionChecker: ScreenshotCapturePermissionChecking {
    func requirePermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ScreenshotDemoCaptureController.CaptureError.permissionRequired
        }
    }
}

private final class ScreenshotDemoSettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScreenshotDemoMenuTarget: NSObject {
    @objc func performDemoAction(_ sender: Any?) {}
}

enum ScreenshotDemoNativeMenu {
    static let orderedTitles = [
        AppMenuAction.showTestReminder.rawValue,
        AppMenuAction.showTaskPanel.rawValue,
        AppMenuAction.hideTaskPanel.rawValue,
        AppMenuLabel.taskPanelCorner,
        AppMenuAction.resetTaskPanelPosition.rawValue,
        AppMenuLabel.allowReminderOverFullScreenApps,
        AppMenuLabel.allowTaskPanelOverFullScreenApps,
        AppMenuAction.refreshTasks.rawValue,
        AppMenuAction.settings.rawValue + "…",
        AppMenuAction.quit.rawValue,
    ]

    @MainActor
    static func makeMenu(target: ScreenshotDemoMenuTarget) -> NSMenu {
        let menu = NSMenu(title: "Nudge")
        menu.autoenablesItems = false
        menu.minimumWidth = 368

        addItem(AppMenuAction.showTestReminder.rawValue, to: menu, target: target)
        menu.addItem(.separator())
        addItem(AppMenuAction.showTaskPanel.rawValue, to: menu, target: target)
        addItem(AppMenuAction.hideTaskPanel.rawValue, to: menu, target: target)

        let cornerItem = addItem(AppMenuLabel.taskPanelCorner, to: menu, target: target)
        let cornerMenu = NSMenu(title: AppMenuLabel.taskPanelCorner)
        for corner in ScreenCorner.allCases {
            addItem(corner.rawValue, to: cornerMenu, target: target)
        }
        cornerItem.submenu = cornerMenu

        addItem(AppMenuAction.resetTaskPanelPosition.rawValue, to: menu, target: target)
        addToggle(AppMenuLabel.allowReminderOverFullScreenApps, to: menu, target: target)
        addToggle(AppMenuLabel.allowTaskPanelOverFullScreenApps, to: menu, target: target)
        addItem(AppMenuAction.refreshTasks.rawValue, to: menu, target: target)
        menu.addItem(.separator())

        let settingsItem = addItem(
            AppMenuAction.settings.rawValue + "…",
            to: menu,
            target: target
        )
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]

        let quitItem = addItem(
            AppMenuAction.quit.rawValue,
            to: menu,
            target: target
        )
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        return menu
    }

    @discardableResult
    @MainActor
    private static func addItem(
        _ title: String,
        to menu: NSMenu,
        target: ScreenshotDemoMenuTarget
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(ScreenshotDemoMenuTarget.performDemoAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.isEnabled = true
        menu.addItem(item)
        return item
    }

    @MainActor
    private static func addToggle(
        _ title: String,
        to menu: NSMenu,
        target: ScreenshotDemoMenuTarget
    ) {
        let item = addItem(title, to: menu, target: target)
        item.state = .off
    }
}

extension ScreenshotDemoCaptureController {
    enum CaptureError: LocalizedError {
        case permissionRequired
        case windowUnavailable
        case menuWindowUnavailable
        case couldNotEncodePNG
        case unsupportedPage

        var errorDescription: String? {
            switch self {
            case .permissionRequired:
                return "Screen Recording permission is required. Enable Nudge in System Settings → Privacy & Security → Screen & System Audio Recording, then run the capture script again."
            case .windowUnavailable:
                return "The Nudge window was not available to the native capture service."
            case .menuWindowUnavailable:
                return "The native Nudge menu did not appear before capture timed out."
            case .couldNotEncodePNG:
                return "The captured Nudge window could not be encoded as PNG."
            case .unsupportedPage:
                return "The requested screenshot page does not have a native window."
            }
        }
    }
}
#endif
