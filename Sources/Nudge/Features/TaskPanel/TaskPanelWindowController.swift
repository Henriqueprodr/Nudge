import AppKit
import SwiftUI

@MainActor
final class TaskPanelWindowController: NSObject, NSWindowDelegate {
    static let panelWidth: CGFloat = 346
    static let compactHeight: CGFloat = 146
    static let defaultExpandedHeight: CGFloat = 254
    static let edgeInset: CGFloat = 16

    private struct VerticalResizeSession {
        let startingFrame: CGRect
        let edge: TaskPanelResizeEdge
        let screen: ScreenDescriptor
    }

    private(set) var panelWindow: TaskPanelWindow?
    private let store: TaskPanelStore
    private let screenProvider: any ScreenProviding
    private var isApplyingFrame = false
    private var geometryPersistenceTask: Task<Void, Never>?
    private var verticalResizeSession: VerticalResizeSession?

    var corner: ScreenCorner {
        get {
            store.state.corner
        }
        set {
            store.setCorner(newValue)
            reposition()
        }
    }

    var presentsOverFullScreenApplications = false {
        didSet {
            applyCollectionBehavior()
        }
    }

    var joinsAllSpaces = true {
        didSet {
            applyCollectionBehavior()
        }
    }

    var isVisible: Bool {
        panelWindow?.isVisible ?? false
    }

    var screenIdentifier: String? {
        store.state.screenIdentifier
    }

    var displayMode: TaskPanelState.DisplayMode {
        store.state.displayMode
    }

    var placementMode: TaskPanelState.PlacementMode {
        store.state.placementMode
    }

    var opacity: Double {
        store.state.opacity
    }

    var priorityPalette: TaskPriorityPalette {
        store.state.priorityPalette
    }

    var windowFrame: CGRect? {
        panelWindow?.frame
    }

    var windowCollectionBehavior: NSWindow.CollectionBehavior? {
        panelWindow?.collectionBehavior
    }

    var windowMinimumSize: CGSize? {
        panelWindow?.minSize
    }

    var windowMaximumSize: CGSize? {
        panelWindow?.maxSize
    }

    init(store: TaskPanelStore, screenProvider: any ScreenProviding = SystemScreenProvider()) {
        self.store = store
        self.screenProvider = screenProvider
        super.init()
    }

    func show() {
        store.setEnabled(true)
        showWindow()
    }

    func restoreIfEnabled() {
        guard store.state.isEnabled else {
            return
        }
        showWindow()
    }

    func reloadCache() {
        store.restore()
    }

    func prepareForSleep() {
        flushGeometryPersistence()
        store.prepareForSleep()
    }

    func recoverAfterLifecycleChange() {
        store.recoverAfterLifecycleChange()
        reposition()
    }

    func setScreenIdentifier(_ identifier: String?) {
        store.setScreenIdentifier(identifier)
        reposition()
    }

    func setDisplayMode(_ mode: TaskPanelState.DisplayMode) {
        verticalResizeSession = nil
        store.setDisplayMode(mode)
        reposition()
    }

    func setPlacementMode(_ mode: TaskPanelState.PlacementMode) {
        guard store.state.placementMode != mode else {
            return
        }
        switch mode {
        case .anchored:
            flushGeometryPersistence()
            store.setPlacementMode(.anchored)
        case .custom:
            if store.state.normalizedPosition == nil,
               let screen = targetScreen() {
                let frame = panelWindow?.frame ?? ScreenPlacement.cornerFrame(
                    contentSize: contentSize(on: screen),
                    in: screen.visibleFrame,
                    corner: corner,
                    edgeInset: Self.edgeInset
                )
                let position = ScreenPlacement.normalizedPosition(
                    for: frame,
                    in: screen.visibleFrame,
                    edgeInset: Self.edgeInset
                )
                store.setCustomPlacement(
                    screenIdentifier: screen.id,
                    position: position
                )
            } else {
                store.setPlacementMode(.custom)
            }
        }
        reposition()
    }

    func setOpacity(_ opacity: Double) {
        store.setOpacity(opacity)
        applyOpacity()
    }

    func setPriorityColor(_ colorHex: String, for priority: TaskPriority) {
        store.setPriorityPalette(store.state.priorityPalette.updating(priority, colorHex: colorHex))
    }

    func resetPosition() {
        store.resetPosition()
        reposition()
    }

    func configureActions(_ actionCoordinator: GoogleTasksActionCoordinator) {
        store.configureActions(actionCoordinator)
    }

    func hide() {
        verticalResizeSession = nil
        flushGeometryPersistence()
        store.setEnabled(false)
        panelWindow?.orderOut(nil)
    }

    func reposition() {
        guard let window = panelWindow, let screen = targetScreen() else {
            return
        }
        configureSizeConstraints(for: window, on: screen)
        let size = contentSize(on: screen)
        let frame: CGRect
        if store.state.placementMode == .custom,
           let normalizedPosition = store.state.normalizedPosition {
            frame = ScreenPlacement.customFrame(
                contentSize: size,
                in: screen.visibleFrame,
                normalizedPosition: normalizedPosition,
                edgeInset: Self.edgeInset
            )
        } else {
            frame = ScreenPlacement.cornerFrame(
                contentSize: size,
                in: screen.visibleFrame,
                corner: corner,
                edgeInset: Self.edgeInset
            )
        }
        apply(frame, to: window)
    }

    func windowDidMove(_ notification: Notification) {
        guard
            !isApplyingFrame,
            let window = notification.object as? NSWindow,
            window === panelWindow,
            !window.inLiveResize
        else {
            return
        }
        guard store.state.placementMode == .custom else {
            reposition()
            return
        }
        recordCustomPlacement(for: window, persistImmediately: false)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard
            !isApplyingFrame,
            store.state.displayMode == .expanded,
            let window = notification.object as? NSWindow
        else {
            return
        }
        commitResize(for: window)
    }

    func beginVerticalResize(from edge: TaskPanelResizeEdge) {
        guard
            store.state.displayMode == .expanded,
            let window = panelWindow,
            let screen = screen(containingMostOf: window.frame) ?? targetScreen()
        else {
            return
        }
        flushGeometryPersistence()
        verticalResizeSession = VerticalResizeSession(
            startingFrame: window.frame,
            edge: edge,
            screen: screen
        )
    }

    func updateVerticalResize(screenTranslation: CGFloat) {
        guard let session = verticalResizeSession, let window = panelWindow else {
            return
        }
        let availableFrame = session.screen.visibleFrame.insetBy(
            dx: Self.edgeInset,
            dy: Self.edgeInset
        )
        let maximumHeight: CGFloat
        let requestedHeight: CGFloat
        switch session.edge {
        case .top:
            maximumHeight = availableFrame.maxY - session.startingFrame.minY
            requestedHeight = session.startingFrame.height + screenTranslation
        case .bottom:
            maximumHeight = session.startingFrame.maxY - availableFrame.minY
            requestedHeight = session.startingFrame.height - screenTranslation
        }
        let clampedMaximumHeight = max(maximumHeight, 1)
        let minimumHeight = min(Self.compactHeight, clampedMaximumHeight)
        let height = min(max(requestedHeight, minimumHeight), clampedMaximumHeight)
        var frame = session.startingFrame
        frame.size.height = height
        if session.edge == .bottom {
            frame.origin.y = session.startingFrame.maxY - height
        }
        apply(frame, to: window)
    }

    func endVerticalResize() {
        guard verticalResizeSession != nil, let window = panelWindow else {
            return
        }
        verticalResizeSession = nil
        commitResize(for: window)
    }

    private func showWindow() {
        let window = panelWindow ?? makeWindow()
        panelWindow = window
        reposition()
        applyOpacity()
        window.orderFrontRegardless()
    }

    private func makeWindow() -> TaskPanelWindow {
        let screen = targetScreen()
        let window = TaskPanelWindow(
            contentRect: CGRect(origin: .zero, size: contentSize(on: screen))
        )
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: TaskPanelView(
                store: store,
                onHide: { [weak self] in
                    self?.hide()
                },
                onToggleDisplayMode: { [weak self] in
                    self?.toggleDisplayMode()
                },
                onResizeBegan: { [weak self] edge in
                    self?.beginVerticalResize(from: edge)
                },
                onResizeChanged: { [weak self] translation in
                    self?.updateVerticalResize(screenTranslation: translation)
                },
                onResizeEnded: { [weak self] in
                    self?.endVerticalResize()
                }
            )
        )
        if let screen {
            configureSizeConstraints(for: window, on: screen)
        }
        applyCollectionBehavior(to: window)
        return window
    }

    private func applyCollectionBehavior() {
        guard let window = panelWindow else {
            return
        }
        applyCollectionBehavior(to: window)
    }

    private func applyCollectionBehavior(to window: NSWindow) {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle]
        if joinsAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        if presentsOverFullScreenApplications {
            behavior.insert(.fullScreenAuxiliary)
        }
        window.collectionBehavior = behavior
    }

    private func applyOpacity() {
        // SwiftUI applies the configured opacity and dynamically overrides it for
        // Reduce Transparency / Increase Contrast. Keep AppKit window alpha opaque.
        panelWindow?.alphaValue = 1
    }

    private func apply(_ frame: CGRect, to window: NSWindow) {
        isApplyingFrame = true
        window.setFrame(frame, display: true)
        isApplyingFrame = false
    }

    private func contentSize(on screen: ScreenDescriptor?) -> CGSize {
        let requestedHeight = store.state.displayMode == .compact
            ? Self.compactHeight
            : CGFloat(store.state.expandedHeight)
        guard let screen else {
            return CGSize(width: Self.panelWidth, height: requestedHeight)
        }
        return CGSize(
            width: min(Self.panelWidth, maximumPanelWidth(on: screen)),
            height: min(requestedHeight, maximumPanelHeight(on: screen))
        )
    }

    private func configureSizeConstraints(for window: NSWindow, on screen: ScreenDescriptor) {
        let width = min(Self.panelWidth, maximumPanelWidth(on: screen))
        let maximumHeight = maximumPanelHeight(on: screen)
        let minimumHeight = min(Self.compactHeight, maximumHeight)
        let constrainedMaximumHeight = store.state.displayMode == .compact
            ? minimumHeight
            : maximumHeight
        window.minSize = CGSize(width: width, height: minimumHeight)
        window.maxSize = CGSize(width: width, height: constrainedMaximumHeight)
    }

    private func maximumPanelWidth(on screen: ScreenDescriptor) -> CGFloat {
        max(screen.visibleFrame.width - Self.edgeInset * 2, 1)
    }

    private func maximumPanelHeight(on screen: ScreenDescriptor) -> CGFloat {
        max(screen.visibleFrame.height - Self.edgeInset * 2, 1)
    }

    private func targetScreen() -> ScreenDescriptor? {
        if let identifier = store.state.screenIdentifier,
           let selected = screenProvider.screens.first(where: { $0.id == identifier }) {
            return selected
        }
        return screenProvider.mainScreen ?? screenProvider.screens.first
    }

    private func screen(containingMostOf frame: CGRect) -> ScreenDescriptor? {
        guard let screen = screenProvider.screens.max(by: { lhs, rhs in
            intersectionArea(of: frame, with: lhs.visibleFrame)
                < intersectionArea(of: frame, with: rhs.visibleFrame)
        }) else {
            return nil
        }
        return intersectionArea(of: frame, with: screen.visibleFrame) > 0 ? screen : nil
    }

    private func intersectionArea(of lhs: CGRect, with rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }

    private func recordCustomPlacement(for window: NSWindow, persistImmediately: Bool) {
        guard let screen = screen(containingMostOf: window.frame) ?? targetScreen() else {
            return
        }
        let position = ScreenPlacement.normalizedPosition(
            for: window.frame,
            in: screen.visibleFrame,
            edgeInset: Self.edgeInset
        )
        store.setCustomPlacement(
            screenIdentifier: screen.id,
            position: position,
            persist: persistImmediately
        )
        if persistImmediately {
            geometryPersistenceTask?.cancel()
            geometryPersistenceTask = nil
        } else {
            scheduleGeometryPersistence()
        }
    }

    private func commitResize(for window: NSWindow) {
        guard store.state.displayMode == .expanded else {
            reposition()
            return
        }
        let screen = screen(containingMostOf: window.frame) ?? targetScreen()
        let maximumHeight = screen.map(maximumPanelHeight(on:)) ?? window.frame.height
        let height = min(max(window.frame.height, Self.compactHeight), maximumHeight)
        store.setExpandedHeight(Double(height), persist: false)

        if store.state.placementMode == .anchored {
            reposition()
            store.persistCurrentState()
        } else {
            recordCustomPlacement(for: window, persistImmediately: true)
        }
    }

    private func scheduleGeometryPersistence() {
        geometryPersistenceTask?.cancel()
        geometryPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            self?.store.persistCurrentState()
            self?.geometryPersistenceTask = nil
        }
    }

    private func flushGeometryPersistence() {
        guard geometryPersistenceTask != nil else {
            return
        }
        geometryPersistenceTask?.cancel()
        geometryPersistenceTask = nil
        store.persistCurrentState()
    }

    private func toggleDisplayMode() {
        setDisplayMode(store.state.displayMode == .compact ? .expanded : .compact)
    }
}
