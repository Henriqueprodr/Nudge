import AppKit
import Observation
import SwiftUI

/// Owns the mascot window and scripts the bird's visits.
///
/// This is an independent window owner: it shares no state with the reminder overlay or the
/// task panel and only reads the overlay's frame, through a closure, so the bird can perch on
/// it. Animation runs only while the bird is visible.
@MainActor
@Observable
final class MascotController {
    typealias OverlayFrameProvider = @MainActor () -> CGRect?
    typealias QuietHoursProvider = @MainActor (Date) -> Bool

    private let screenProvider: any ScreenProviding
    private let settingsRepository: any MascotSettingsRepository
    @ObservationIgnored private let lineBook: MascotLineBook
    @ObservationIgnored private let synth = BirdWhistleSynth()
    @ObservationIgnored private let dockReader = DockGeometryReader()
    @ObservationIgnored private let overlayFrame: OverlayFrameProvider
    @ObservationIgnored private let isQuietHours: QuietHoursProvider
    private let now: @MainActor () -> Date
    private let reduceMotion: @MainActor () -> Bool

    @ObservationIgnored private let scene = MascotScene()
    @ObservationIgnored private var window: MascotWindow?
    @ObservationIgnored private var hostingView: NSHostingView<MascotSceneView>?
    @ObservationIgnored private var screenFrame: CGRect = .zero
    @ObservationIgnored private var scriptTask: Task<Void, Never>?
    @ObservationIgnored private var idleTimer: Timer?
    @ObservationIgnored private var hoverTimer: Timer?
    @ObservationIgnored private var recentLines: [String] = []

    private(set) var settings: MascotSettings
    private(set) var nextIdleVisitDate: Date?
    private(set) var isPerformingVisit = false

    init(
        screenProvider: any ScreenProviding = SystemScreenProvider(),
        settingsRepository: any MascotSettingsRepository = UserDefaultsMascotSettingsRepository(),
        lineBook: MascotLineBook = .load(),
        overlayFrame: @escaping OverlayFrameProvider = { nil },
        isQuietHours: @escaping QuietHoursProvider = { _ in false },
        now: @escaping @MainActor () -> Date = Date.init,
        reduceMotion: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        self.screenProvider = screenProvider
        self.settingsRepository = settingsRepository
        self.lineBook = lineBook
        self.overlayFrame = overlayFrame
        self.isQuietHours = isQuietHours
        self.now = now
        self.reduceMotion = reduceMotion
        settings = (settingsRepository.fetchSettings() ?? .defaultValue).validated
    }

    // MARK: Settings and scheduling

    func start() {
        scheduleNextIdleVisit()
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        scriptTask?.cancel()
        hide()
    }

    func updateSettings(_ newSettings: MascotSettings) {
        settings = newSettings.validated
        settingsRepository.save(settings)
        if !settings.isEnabled {
            scriptTask?.cancel()
            hide()
        }
        scheduleNextIdleVisit()
    }

    func muteForOneHour() {
        var updated = settings
        updated.doNotDisturbUntil = now().addingTimeInterval(3_600)
        updateSettings(updated)
        scriptTask?.cancel()
        hide()
    }

    func goAwayForToday() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now())
        ) ?? now().addingTimeInterval(86_400)
        var updated = settings
        updated.doNotDisturbUntil = tomorrow
        updateSettings(updated)
        scriptTask?.cancel()
        hide()
    }

    func clearDoNotDisturb() {
        var updated = settings
        updated.doNotDisturbUntil = nil
        updateSettings(updated)
    }

    var isMuted: Bool {
        settings.doNotDisturbUntil.map { $0 > now() } ?? false
    }

    private func scheduleNextIdleVisit() {
        idleTimer?.invalidate()
        idleTimer = nil
        nextIdleVisitDate = nil
        guard settings.isEnabled, settings.makesIdleVisits else { return }
        let base = TimeInterval(settings.idleVisitIntervalMinutes * 60)
        let delay = base * Double.random(in: 0.67...1.33)
        let fireDate = now().addingTimeInterval(delay)
        nextIdleVisitDate = fireDate
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.idleTimerFired()
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func idleTimerFired() {
        defer { scheduleNextIdleVisit() }
        let date = now()
        guard !settings.isQuiet(at: date),
              !isQuietHours(date),
              !isPerformingVisit,
              NSMenu.menuBarVisible() else { return }
        performIdleVisit()
    }

    // MARK: Entry points

    /// Brings the bird out now, from the menu. Ignores Do Not Disturb.
    func summon() {
        guard settings.isEnabled else { return }
        performIdleVisit()
    }

    /// Called when an alert reaches the screen.
    func deliver(_ reminder: Reminder) {
        guard settings.isEnabled, settings.deliversAlerts, !settings.isQuiet(at: now()) else {
            return
        }
        let presentation = ReminderStripPresentation(reminder: reminder, now: now())
        let category = MascotLineCategory(tone: presentation.tone)
        let days = reminder.taskContext.map { context in
            String(context.daysOverdue.flatMap { $0 > 0 ? $0 : nil } ?? context.daysOpen)
        } ?? ""
        let line = pickLine(category, substitutions: [
            "task": reminder.title,
            "event": reminder.title,
            "days": days,
            "count": String(reminder.taskContext?.taskIDs.count ?? 1),
        ])
        run { controller in
            // Give the overlay a moment to settle into its resting frame.
            try await controller.pause(0.35)
            if let card = controller.overlayFrame() {
                try await controller.perch(on: card, saying: line)
            } else {
                try await controller.dockVisit(saying: line, whistle: false)
            }
        }
    }

    /// A short celebration after a task is completed from an alert.
    func celebrateTaskDone() {
        guard settings.isEnabled, !settings.isQuiet(at: now()) else { return }
        let line = pickLine(.taskDone)
        run { controller in
            try await controller.dockVisit(saying: line, whistle: true, call: .trill)
        }
    }

    private func performIdleVisit() {
        let line = pickLine(.idle)
        let call: BirdWhistleSynth.Call = settings.spice == .unhinged ? .wolfWhistle : .chirp
        run { controller in
            try await controller.dockVisit(saying: line, whistle: true, call: call)
        }
    }

    private func poke() {
        guard scene.isVisible, scene.speech != nil else { return }
        scene.speech = pickLine(.poked)
        if settings.whistles {
            synth.play(.trill, volume: 0.25)
        }
    }

    private func pickLine(
        _ category: MascotLineCategory,
        substitutions: [String: String] = [:]
    ) -> String {
        let line = lineBook.line(
            for: category,
            spice: settings.spice,
            substitutions: substitutions,
            avoiding: Set(recentLines)
        )
        recentLines.append(line)
        if recentLines.count > 12 { recentLines.removeFirst() }
        return line
    }

    // MARK: Scripts

    private func run(_ script: @escaping @MainActor (MascotController) async throws -> Void) {
        scriptTask?.cancel()
        isPerformingVisit = true
        scriptTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await script(self)
            } catch {}
            if !Task.isCancelled {
                self.hide()
                self.isPerformingVisit = false
            }
        }
    }

    /// Fly onto the Dock (or screen bottom), walk, turn to the viewer, talk, and leave.
    private func dockVisit(
        saying line: String,
        whistle: Bool,
        call: BirdWhistleSynth.Call = .chirp
    ) async throws {
        guard let screen = screenProvider.pointerScreen ?? screenProvider.mainScreen else { return }
        prepareWindow(on: screen)
        let ground = MascotGround.resolve(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            dock: dockReader.read(dockThickness: screen.visibleFrame.minY - screen.frame.minY)
        )
        let fromLeft = Bool.random()
        let landingX = fromLeft
            ? ground.xRange.lowerBound + 20
            : ground.xRange.upperBound - 20
        let span = ground.xRange.upperBound - ground.xRange.lowerBound
        let stopX = fromLeft
            ? min(landingX + span * Double.random(in: 0.2...0.45), ground.xRange.upperBound)
            : max(landingX - span * Double.random(in: 0.2...0.45), ground.xRange.lowerBound)
        let groundY = local(y: ground.y)
        scene.scale = 1
        scene.facesLeft = !fromLeft

        if reduceMotion() {
            scene.position = CGPoint(x: local(x: stopX), y: groundY)
            try await fadeIn()
        } else {
            let entryX = fromLeft ? -40 : screen.frame.width + 40
            scene.position = CGPoint(x: entryX, y: groundY - 220)
            scene.motion = .flying
            scene.opacity = 1
            scene.isVisible = true
            try await move(to: CGPoint(x: local(x: landingX), y: groundY), duration: 1.3, curve: .easeOut)
            scene.motion = .walking
            try await move(
                to: CGPoint(x: local(x: stopX), y: groundY),
                duration: abs(stopX - landingX) / 70,
                curve: .linear
            )
        }

        scene.motion = .lookingAtViewer
        try await pause(0.35)
        if whistle, settings.whistles {
            synth.play(call)
            try await pause(0.4)
        }
        scene.bubblePlacement = .above
        try await speak(line)
        scene.motion = .standing
        try await pause(0.2)

        if reduceMotion() {
            try await fadeOut()
        } else {
            scene.speech = nil
            scene.facesLeft.toggle()
            scene.motion = .flying
            let exitX = scene.facesLeft ? -60 : screen.frame.width + 60
            try await move(to: CGPoint(x: exitX, y: groundY - 260), duration: 1.2, curve: .easeIn)
        }
    }

    /// Fly onto the alert card's top edge and comment on it.
    private func perch(on card: CGRect, saying line: String) async throws {
        guard let screen = screenProvider.screens.first(where: { $0.frame.intersects(card) })
            ?? screenProvider.mainScreen else { return }
        prepareWindow(on: screen)
        scene.scale = 0.8
        let perchX = local(x: card.minX + 34)
        let perchY = local(y: card.maxY - 2)
        let spaceOnLeading = card.minX - screen.frame.minX
        scene.bubblePlacement = spaceOnLeading > 280 ? .leading : .below
        scene.facesLeft = false

        if reduceMotion() {
            scene.position = CGPoint(x: perchX, y: perchY)
            try await fadeIn()
        } else {
            scene.position = CGPoint(x: -40, y: perchY + 120)
            scene.motion = .flying
            scene.opacity = 1
            scene.isVisible = true
            try await move(to: CGPoint(x: perchX, y: perchY), duration: 1.1, curve: .easeOut)
        }
        scene.motion = .lookingAtViewer
        try await pause(0.25)
        try await speak(line, hold: 5.5)

        if reduceMotion() {
            try await fadeOut()
        } else {
            scene.speech = nil
            scene.facesLeft = true
            scene.motion = .flying
            try await move(to: CGPoint(x: -60, y: perchY - 40), duration: 1.0, curve: .easeIn)
        }
    }

    private func speak(_ line: String, hold: TimeInterval? = nil) async throws {
        scene.isTalking = true
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
            scene.speech = line
        }
        try await pause(0.9)
        scene.isTalking = false
        let reading = hold ?? min(max(Double(line.count) / 14, 3.2), 7)
        try await pause(reading)
        withAnimation(.easeIn(duration: 0.2)) {
            scene.speech = nil
        }
        try await pause(0.2)
    }

    // MARK: Motion primitives

    private enum Curve {
        case linear
        case easeIn
        case easeOut
    }

    private func move(to point: CGPoint, duration: TimeInterval, curve: Curve) async throws {
        let animation: Animation
        switch curve {
        case .linear: animation = .linear(duration: duration)
        case .easeIn: animation = .easeIn(duration: duration)
        case .easeOut: animation = .easeOut(duration: duration)
        }
        withAnimation(animation) {
            scene.position = point
        }
        try await pause(duration)
    }

    private func fadeIn() async throws {
        scene.motion = .standing
        scene.isVisible = true
        withAnimation(.easeOut(duration: 0.25)) { scene.opacity = 1 }
        try await pause(0.25)
    }

    private func fadeOut() async throws {
        withAnimation(.easeIn(duration: 0.25)) {
            scene.opacity = 0
            scene.speech = nil
        }
        try await pause(0.25)
    }

    private func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Window

    private func prepareWindow(on screen: ScreenDescriptor) {
        screenFrame = screen.frame
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        startHoverTracking()
    }

    private func makeWindow() -> MascotWindow {
        let window = MascotWindow(frame: screenFrame)
        let hostingView = NSHostingView(
            rootView: MascotSceneView(
                scene: scene,
                onPoke: { [weak self] in self?.poke() },
                onMute: { [weak self] in self?.muteForOneHour() },
                onGoAwayToday: { [weak self] in self?.goAwayForToday() }
            )
        )
        hostingView.sizingOptions = []
        window.contentView = hostingView
        self.hostingView = hostingView
        return window
    }

    private func hide() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        scene.speech = nil
        scene.isVisible = false
        scene.opacity = 0
        scene.motion = .standing
        scene.isTalking = false
        window?.ignoresMouseEvents = true
        window?.orderOut(nil)
        isPerformingVisit = false
    }

    /// The window is click-through except while the pointer is over the bird, so clicking the
    /// bird works without the transparent window ever blocking the desktop.
    private func startHoverTracking() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMousePassthrough()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateMousePassthrough() {
        guard let window, scene.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        let localPointer = CGPoint(x: local(x: pointer.x), y: local(y: pointer.y))
        let isOverBird = scene.birdFrame.insetBy(dx: -6, dy: -6).contains(localPointer)
        if window.ignoresMouseEvents == isOverBird {
            window.ignoresMouseEvents = !isOverBird
        }
    }

    private func local(x: CGFloat) -> CGFloat {
        x - screenFrame.minX
    }

    private func local(y: CGFloat) -> CGFloat {
        screenFrame.maxY - y
    }
}
