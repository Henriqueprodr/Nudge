import SwiftUI

/// Root content of the reminder window: maps store state onto the control strip and applies the
/// in-place entry and timed-exit scale transitions. Window fading is owned by
/// `ReminderOverlayWindowController`.
struct ReminderOverlayView: View {
    let store: ReminderOverlayStore
    let onDismiss: () -> Void
    let onSnooze: () -> Void
    let onOpen: () -> Void
    let onAction: (ReminderAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentationScale = ReminderStripStyle.transitionScale

    var body: some View {
        Group {
            if let presentation = store.stripPresentation {
                WholePointLayout {
                    ReminderControlStripView(
                    presentation: presentation,
                    isPerformingAction: store.isPerformingAction,
                    actionErrorMessage: store.actionErrorMessage,
                    onOpen: onOpen,
                    onSnooze: onSnooze,
                    onDismiss: onDismiss,
                    onAction: onAction
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .scaleEffect(reduceMotion ? 1 : presentationScale, anchor: .center)
        .task(id: store.presentationToken) {
            presentationScale = reduceMotion ? 1 : ReminderStripStyle.transitionScale
            guard !reduceMotion else { return }
            await Task.yield()
            withAnimation(
                .spring(
                    duration: ReminderStripStyle.entryDuration,
                    bounce: ReminderStripStyle.entryBounce
                )
            ) {
                presentationScale = 1
            }
        }
        .onChange(of: store.isAnimatingOut) { _, isAnimatingOut in
            guard isAnimatingOut, !reduceMotion else { return }
            withAnimation(.easeIn(duration: ReminderStripStyle.exitDuration)) {
                presentationScale = ReminderStripStyle.transitionScale
            }
        }
    }
}
