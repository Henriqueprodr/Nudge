import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class ReminderOverlayWindowController: NSObject {
    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void
    /// Animates the window towards `endAlpha`. Injected so tests never depend on real Core
    /// Animation timing.
    typealias AlphaAnimator = @MainActor (
        _ window: NSWindow,
        _ endAlpha: CGFloat,
        _ duration: TimeInterval
    ) -> Void

    /// Fallback size used only before the strip has been measured, e.g. when no screen is
    /// available. Real presentations size the window from `NSHostingView.fittingSize`.
    private static let unmeasuredContentSize = CGSize(width: 525, height: 105)

    private var overlayWindow: ReminderOverlayWindow?
    private var hostingView: NSHostingView<ReminderOverlayView>?
    private let store: ReminderOverlayStore
    private var onDismiss: (() -> Void)?
    private var onSnooze: (() -> Void)?
    private var onOpen: (() -> Void)?
    private var onAction: ((ReminderAction) -> Void)?
    private let screenProvider: any ScreenProviding
    private let presentationAvailability: ((NSWindow) -> Bool)?
    private let reduceMotion: @MainActor () -> Bool
    private let sleeper: Sleeper
    private let alphaAnimator: AlphaAnimator
    private let now: @MainActor () -> Date
    private var presentationTask: Task<Void, Never>?

    var displayTarget: PresentationSettings.ReminderDisplayTarget = .pointer
    var presentationDuration = ReminderPresentationDuration.defaultValue
    var persistsUntilAction = false

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
        overlayWindow?.isVisible ?? false
    }

    var presentedReminder: Reminder? {
        store.reminder
    }

    var windowFrame: CGRect? {
        overlayWindow?.frame
    }

    /// The alert window, exposed for layout regression tests.
    var window: NSWindow? {
        overlayWindow
    }

    var windowCollectionBehavior: NSWindow.CollectionBehavior? {
        overlayWindow?.collectionBehavior
    }

    init(
        store: ReminderOverlayStore,
        screenProvider: any ScreenProviding = SystemScreenProvider(),
        presentationAvailability: ((NSWindow) -> Bool)? = nil,
        reduceMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        alphaAnimator: @escaping AlphaAnimator =
            ReminderOverlayWindowController.animateWindowAlpha,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.store = store
        self.screenProvider = screenProvider
        self.presentationAvailability = presentationAvailability
        self.reduceMotion = reduceMotion
        self.sleeper = sleeper
        self.alphaAnimator = alphaAnimator
        self.now = now
        super.init()
    }

    func present(
        _ reminder: Reminder,
        onDismiss: @escaping () -> Void,
        onSnooze: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onAction: @escaping (ReminderAction) -> Void = { _ in },
        onPresentationResult: @escaping (Bool) -> Void
    ) {
        presentationTask?.cancel()
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
        self.onOpen = onOpen
        self.onAction = onAction
        store.present(reminder, now: now())
        let presentationToken = store.presentationToken
        let window = overlayWindow ?? makeWindow()
        overlayWindow = window
        let restingFrame = reposition() ?? window.frame
        animateEntrance(of: window, to: restingFrame)
        window.orderFrontRegardless()
        scheduleTimedExitIfNeeded()
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else {
                onPresentationResult(false)
                return
            }
            guard self.store.presentationToken == presentationToken,
                  self.store.reminder?.occurrenceID == reminder.occurrenceID else {
                return
            }
            onPresentationResult(
                self.presentationAvailability?(window) ?? window.isOnActiveSpace
            )
        }
    }

    /// Immediate teardown used by explicit dismissal, snooze, and coordinator-driven cleanup.
    func dismiss() {
        presentationTask?.cancel()
        presentationTask = nil
        overlayWindow?.orderOut(nil)
        overlayWindow?.alphaValue = 1
        store.clear()
        onDismiss = nil
        onSnooze = nil
        onOpen = nil
        onAction = nil
    }

    /// Re-measures the strip and moves it to its upper-center resting frame.
    @discardableResult
    func reposition() -> CGRect? {
        guard let window = overlayWindow, let screen = targetScreen() else {
            return nil
        }
        let frame = restingFrame(in: screen.visibleFrame)
        window.setFrame(frame, display: true)
        return frame
    }

    func beginAction() {
        presentationTask?.cancel()
        presentationTask = nil
        store.beginAction()
    }

    func endAction(errorMessage: String? = nil) {
        store.endAction(errorMessage: errorMessage)
    }

    private func makeWindow() -> ReminderOverlayWindow {
        let window = ReminderOverlayWindow(
            contentRect: CGRect(origin: .zero, size: Self.unmeasuredContentSize)
        )
        let hostingView = NSHostingView(
            rootView: ReminderOverlayView(
                store: store,
                onDismiss: { [weak self] in
                    self?.onDismiss?()
                },
                onSnooze: { [weak self] in
                    self?.onSnooze?()
                },
                onOpen: { [weak self] in
                    self?.onOpen?()
                },
                onAction: { [weak self] action in
                    self?.onAction?(action)
                }
            )
        )
        self.hostingView = hostingView
        window.contentView = hostingView
        applyCollectionBehavior(to: window)
        return window
    }

    /// The window needs a concrete frame, so the strip is measured rather than hard-coded: the
    /// SwiftUI content reports its intrinsic size and only the width is bounded, by a documented
    /// minimum and by whichever is smaller of the style maximum and the display's usable width.
    /// A second measurement at the selected width lets accessibility wrapping determine height.
    private func restingFrame(in visibleFrame: CGRect) -> CGRect {
        ScreenPlacement.reminderStripFrame(
            contentSize: measuredContentSize(in: visibleFrame),
            in: visibleFrame,
            topInset: ReminderStripStyle.screenTopInset,
            horizontalInset: ReminderStripStyle.screenHorizontalInset
        )
    }

    private func measuredContentSize(in visibleFrame: CGRect) -> CGSize {
        guard let hostingView else {
            return Self.unmeasuredContentSize
        }
        hostingView.layoutSubtreeIfNeeded()
        let intrinsic = hostingView.fittingSize
        guard intrinsic.width > 0, intrinsic.height > 0 else {
            return Self.unmeasuredContentSize
        }
        let availableWidth = max(
            visibleFrame.width - ReminderStripStyle.screenHorizontalInset * 2,
            0
        )
        let maximumWidth = min(
            ReminderStripStyle.maximumWidth,
            availableWidth
        )
        let minimumWidth = min(ReminderStripStyle.minimumWidth, maximumWidth)
        let selectedWidth = min(max(intrinsic.width, minimumWidth), maximumWidth)
        hostingView.setFrameSize(CGSize(width: selectedWidth, height: intrinsic.height))
        hostingView.layoutSubtreeIfNeeded()
        let constrained = hostingView.fittingSize
        return CGSize(width: selectedWidth, height: max(intrinsic.height, constrained.height))
    }

    private func animateEntrance(of window: NSWindow, to restingFrame: CGRect) {
        window.setFrame(restingFrame, display: false)
        window.alphaValue = 0
        let duration = reduceMotion()
            ? ReminderStripStyle.reducedMotionDuration
            : ReminderStripStyle.entryDuration
        alphaAnimator(window, 1, duration)
    }

    /// Automatic expiry pops and fades the strip away before the scheduler records dismissal.
    private func animateExit(of window: NSWindow) {
        store.beginExitAnimation()
        alphaAnimator(window, 0, exitAnimationDuration)
    }

    private var exitAnimationDuration: TimeInterval {
        reduceMotion() ? ReminderStripStyle.reducedMotionDuration : ReminderStripStyle.exitDuration
    }

    private func applyCollectionBehavior() {
        guard let window = overlayWindow else {
            return
        }
        applyCollectionBehavior(to: window)
    }

    private func applyCollectionBehavior(to window: NSWindow) {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .transient]
        if joinsAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        if presentsOverFullScreenApplications {
            behavior.insert(.fullScreenAuxiliary)
        }
        window.collectionBehavior = behavior
    }

    private func scheduleTimedExitIfNeeded() {
        guard !persistsUntilAction else {
            return
        }
        presentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await sleeper(presentationDuration.timeInterval)
            } catch {
                return
            }
            guard !Task.isCancelled, store.reminder != nil else { return }
            if let window = overlayWindow {
                animateExit(of: window)
                try? await sleeper(exitAnimationDuration)
                guard !Task.isCancelled, store.reminder != nil else { return }
            }
            onDismiss?()
        }
    }

    private func targetScreen() -> ScreenDescriptor? {
        switch displayTarget {
        case .pointer:
            return screenProvider.pointerScreen ?? screenProvider.mainScreen
        case let .fixed(identifier):
            return screenProvider.screens.first(where: { $0.id == identifier })
                ?? screenProvider.mainScreen
        }
    }

    private static func animateWindowAlpha(
        _ window: NSWindow,
        endAlpha: CGFloat,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = endAlpha
        }
    }
}
