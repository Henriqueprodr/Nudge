import SwiftUI

/// Hand-drawn reminder card: a coloured time chip, the event or task, and ink-outlined actions.
///
/// The view owns no state and no timers. It is driven entirely by a `ReminderStripPresentation`
/// so it can be reasoned about, previewed, and measured without a window.
struct ReminderControlStripView: View {
    let presentation: ReminderStripPresentation
    let isPerformingAction: Bool
    let actionErrorMessage: String?
    let onOpen: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    var onAction: (ReminderAction) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: ReminderStripStyle.regionSpacing) {
            timeChip
            eventContent
            actions
        }
        .padding(.horizontal, ReminderStripStyle.horizontalPadding)
        .padding(.vertical, ReminderStripStyle.verticalPadding)
        .background { InkCardBackground(variant: .card) }
        // Leave room for the sticker shadow so the window measures it.
        .padding(.bottom, InkMetrics.stickerOffset)
    }

    private var timeChip: some View {
        VStack(spacing: ReminderStripStyle.lineSpacing) {
            Text(presentation.timeText)
                .font(ReminderStripStyle.timeFont)
                .foregroundStyle(NudgePalette.onBlue)
                .lineLimit(1)
            Text(presentation.dateText)
                .font(ReminderStripStyle.dateFont)
                .tracking(ReminderStripStyle.eyebrowTracking)
                .foregroundStyle(NudgePalette.onBlue.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minWidth: ReminderStripStyle.timeChipMinimumWidth)
        .background {
            ZStack {
                InkShape(variant: .chip)
                    .fill(ReminderStripStyle.accentColor(hex: presentation.accentHex))
                InkShape(variant: .chip)
                    .strokeBorderCompatible(NudgePalette.ink, lineWidth: InkMetrics.thinStrokeWidth)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var eventContent: some View {
        VStack(alignment: .leading, spacing: ReminderStripStyle.lineSpacing) {
            Text(presentation.eyebrow)
                .lineLimit(1)
                .font(ReminderStripStyle.eyebrowFont)
                .tracking(ReminderStripStyle.eyebrowTracking)
                .foregroundStyle(ReminderStripStyle.accentColor(hex: presentation.accentHex))
            Text(presentation.title)
                .font(ReminderStripStyle.titleFont)
                .foregroundStyle(ReminderStripStyle.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
            secondaryLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if let actionErrorMessage {
            Text(actionErrorMessage)
                .font(ReminderStripStyle.metadataFont)
                .foregroundStyle(ReminderStripStyle.warningText)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if let metadata = presentation.metadata {
            Text(metadata)
                .font(ReminderStripStyle.metadataFont)
                .foregroundStyle(ReminderStripStyle.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var actions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: ReminderStripStyle.actionSpacing) {
                    actionControls
                }
            } else {
                HStack(spacing: ReminderStripStyle.actionSpacing) {
                    actionControls
                }
            }
        }
        .fixedSize()
        .disabled(isPerformingAction)
    }

    @ViewBuilder
    private var actionControls: some View {
        ForEach(Array(presentation.actions.enumerated()), id: \.element) { index, action in
            Button(action.title) { onAction(action) }
                .buttonStyle(InkButtonStyle(role: role(for: action, at: index)))
                .accessibilityLabel(action.accessibilityLabel)
        }
        if presentation.hasSource {
            if presentation.actions.isEmpty {
                Button("Open", action: onOpen)
                    .buttonStyle(InkButtonStyle(role: .primary))
                    .keyboardShortcut("o", modifiers: [.command])
                    .accessibilityLabel("Open reminder source")
            } else {
                // With task actions on the card, Open shrinks to an icon so the title fits.
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .buttonStyle(InkButtonStyle(role: .secondary))
                .keyboardShortcut("o", modifiers: [.command])
                .help("Open in Google Tasks")
                .accessibilityLabel("Open reminder source")
            }
        }
        Button(presentation.snoozeTitle, action: onSnooze)
            .buttonStyle(InkButtonStyle(role: .secondary))
            .keyboardShortcut("s", modifiers: [.command])
            .accessibilityLabel(presentation.snoozeAccessibilityLabel)
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
        }
        .buttonStyle(InkButtonStyle(role: .quiet))
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Dismiss reminder")
    }

    private func role(for action: ReminderAction, at index: Int) -> InkButtonStyle.Role {
        switch action {
        case .completeTask:
            return .primary
        case .notToday:
            return index == 0 ? .primary : .secondary
        }
    }
}
