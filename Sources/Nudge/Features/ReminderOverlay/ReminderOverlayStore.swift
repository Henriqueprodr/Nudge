import Foundation
import Observation

@MainActor
@Observable
final class ReminderOverlayStore {
    private(set) var reminder: Reminder?
    /// Built once per presentation so the strip never recomputes relative wording on screen.
    private(set) var stripPresentation: ReminderStripPresentation?
    private(set) var presentationToken = UUID()
    private(set) var actionErrorMessage: String?
    private(set) var isPerformingAction = false
    private(set) var isAnimatingOut = false

    func present(_ reminder: Reminder, now: Date = Date()) {
        self.reminder = reminder
        stripPresentation = ReminderStripPresentation(reminder: reminder, now: now)
        presentationToken = UUID()
        actionErrorMessage = nil
        isPerformingAction = false
        isAnimatingOut = false
    }

    func clear() {
        reminder = nil
        stripPresentation = nil
        actionErrorMessage = nil
        isPerformingAction = false
        isAnimatingOut = false
    }

    func beginExitAnimation() {
        isAnimatingOut = true
    }

    func beginAction() {
        isPerformingAction = true
        actionErrorMessage = nil
    }

    func endAction(errorMessage: String? = nil) {
        isPerformingAction = false
        actionErrorMessage = errorMessage
    }
}
