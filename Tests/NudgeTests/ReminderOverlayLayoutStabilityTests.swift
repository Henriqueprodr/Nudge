import AppKit
import SwiftUI
import XCTest
@testable import Nudge

/// Regression coverage for the installed-build crash where AppKit raised "more Update
/// Constraints in Window passes than there are views" when the bird spoke beside an alert.
final class ReminderOverlayLayoutStabilityTests: XCTestCase {
    @MainActor
    func testEveryAlertKindKeepsAStableFrameThroughRealDisplayCycles() {
        for screen in [Self.laptopScreen, Self.narrowScreen] {
            for reminder in Self.reminders() {
                let controller = Self.controller(screen: screen)
                defer { controller.dismiss() }

                controller.present(
                    reminder,
                    onDismiss: {},
                    onSnooze: {},
                    onOpen: {},
                    onPresentationResult: { _ in }
                )
                guard let initialFrame = controller.windowFrame,
                      let window = controller.window else {
                    XCTFail("No alert window for \(reminder.title)")
                    continue
                }

                for _ in 0..<5 {
                    window.updateConstraintsIfNeeded()
                    window.layoutIfNeeded()
                    window.displayIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                }

                let label = "\(reminder.title) on \(screen.name)"
                XCTAssertEqual(window.frame, initialFrame, "Frame moved after display: \(label)")
                XCTAssertLessThanOrEqual(
                    window.frame.width,
                    min(ReminderStripStyle.maximumWidth, screen.visibleFrame.width),
                    label
                )
                XCTAssertTrue(screen.visibleFrame.contains(window.frame), label)
            }
        }
    }

    /// Mirrors the real app: animated alert, then the bird flies over and perches on it.
    @MainActor
    func testAnimatedAlertWithPerchingBirdSurvivesSeveralSeconds() {
        let screenProvider = SystemScreenProvider()
        for reminder in Self.reminders() {
            let controller = ReminderOverlayWindowController(
                store: ReminderOverlayStore(),
                screenProvider: screenProvider,
                presentationAvailability: { _ in true },
                reduceMotion: { false },
                sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) }
            )
            let mascot = MascotController(
                screenProvider: screenProvider,
                settingsRepository: InMemoryMascotSettingsRepository(),
                lineBook: .load(userFileURL: nil),
                overlayFrame: { [weak controller] in controller?.windowFrame },
                reduceMotion: { false }
            )
            controller.present(
                reminder,
                onDismiss: {},
                onSnooze: {},
                onOpen: {},
                onPresentationResult: { _ in }
            )
            mascot.deliver(reminder)
            let initialFrame = controller.windowFrame
            RunLoop.main.run(until: Date().addingTimeInterval(4))
            XCTAssertEqual(controller.windowFrame, initialFrame, reminder.title)
            mascot.stop()
            controller.dismiss()
        }
    }

    /// The crash itself: a speech bubble in the bird window, in every placement. Before the fix
    /// the bubble's alignment guides grew the root view past the window and AppKit raised.
    @MainActor
    func testBirdSpeechBubbleInEveryPlacementSurvivesRealDisplayCycles() throws {
        let frame = try XCTUnwrap(NSScreen.main?.frame)
        for placement in [MascotScene.BubblePlacement.above, .leading, .below] {
            let window = MascotWindow(frame: frame)
            let scene = MascotScene()
            let host = NSHostingView(rootView: MascotSceneView(scene: scene))
            host.sizingOptions = []
            window.contentView = host
            window.setFrame(frame, display: false)
            window.orderFrontRegardless()
            scene.scale = 0.8
            scene.bubblePlacement = placement
            scene.position = CGPoint(x: 40, y: placement == .above ? frame.height - 20 : 120)
            scene.isVisible = true
            scene.opacity = 1
            scene.motion = .lookingAtViewer
            scene.isTalking = true
            scene.speech = "FYI: this task has been sitting here for nine days and I am tired"
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            XCTAssertEqual(window.frame, frame, "\(placement)")
            window.orderOut(nil)
        }
    }

    // MARK: Fixtures

    private static let laptopScreen = ScreenDescriptor(
        id: "laptop",
        name: "Laptop",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852),
        isMain: true
    )

    private static let narrowScreen = ScreenDescriptor(
        id: "narrow",
        name: "Narrow",
        frame: CGRect(x: 0, y: 0, width: 640, height: 480),
        visibleFrame: CGRect(x: 0, y: 24, width: 640, height: 456),
        isMain: true
    )

    @MainActor
    private static func controller(screen: ScreenDescriptor) -> ReminderOverlayWindowController {
        ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            screenProvider: StabilityScreenProvider(screen: screen),
            presentationAvailability: { _ in true },
            reduceMotion: { true },
            sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) },
            alphaAnimator: { window, endAlpha, _ in window.alphaValue = endAlpha }
        )
    }

    private static func reminders() -> [Reminder] {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func id(_ kind: ReminderOccurrenceID.SourceKind, _ name: String) -> ReminderOccurrenceID {
            ReminderOccurrenceID(
                sourceKind: kind,
                sourceIdentifier: name,
                occurrenceDate: now,
                revision: nil
            )
        }
        let longTitle = String(
            repeating: "Finish the extremely long quarterly report draft and send it ", count: 3
        )
        let taskContext = ReminderTaskContext(
            taskIDs: ["a", "b", "c"],
            primaryTaskListID: "list",
            urgency: .overdue,
            dueDate: TaskItem.DueDate(year: 2026, month: 11, day: 17),
            daysOverdue: 3,
            daysOpen: 9
        )
        return [
            Reminder(
                occurrenceID: id(.task, "nag-long"),
                title: longTitle,
                detail: nil,
                triggerDate: now,
                expirationDate: nil,
                presentationMode: .overlay,
                sourceURL: URL(string: "https://tasks.google.com/"),
                taskContext: taskContext,
                actions: [.completeTask, .notToday]
            ),
            Reminder(
                occurrenceID: id(.task, "nag-short"),
                title: "Taxes",
                detail: nil,
                triggerDate: now,
                expirationDate: nil,
                presentationMode: .overlay,
                sourceURL: URL(string: "https://tasks.google.com/"),
                taskContext: taskContext,
                actions: [.completeTask, .notToday]
            ),
            Reminder(
                occurrenceID: id(.local, "google-reauthentication"),
                title: "Google signed Nudge out",
                detail: "Google ended this session. Your OAuth app is probably still in Testing mode.",
                triggerDate: now,
                expirationDate: nil,
                presentationMode: .overlay,
                actions: [.signIn]
            ),
            Reminder(
                occurrenceID: id(.calendar, "event"),
                title: longTitle,
                detail: "Directly visible on screen",
                triggerDate: now,
                expirationDate: nil,
                presentationMode: .overlay,
                sourceURL: URL(string: "https://calendar.google.com/"),
                eventContext: ReminderEventContext(
                    startDate: now.addingTimeInterval(600),
                    calendarTitle: "Work",
                    location: "Room 4",
                    calendarColorHex: "#3F7DE0"
                )
            ),
        ]
    }
}

@MainActor
private final class StabilityScreenProvider: ScreenProviding {
    let screens: [ScreenDescriptor]

    init(screen: ScreenDescriptor) {
        screens = [screen]
    }

    var mainScreen: ScreenDescriptor? { screens.first }
    var pointerScreen: ScreenDescriptor? { screens.first }
}
