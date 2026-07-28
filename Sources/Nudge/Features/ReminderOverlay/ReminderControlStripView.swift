import SwiftUI

/// Compact horizontal reminder surface: calendar accent, time, event content, actions.
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

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            accent
            HStack(spacing: ReminderStripStyle.regionSpacing) {
                timeRegion
                divider
                eventContent
                actions
            }
            .padding(.horizontal, ReminderStripStyle.horizontalPadding)
            .padding(.vertical, ReminderStripStyle.verticalPadding)
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: ReminderStripStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReminderStripStyle.cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    private var accent: some View {
        Rectangle()
            .fill(ReminderStripStyle.accentColor(hex: presentation.accentHex))
            .frame(width: ReminderStripStyle.accentWidth)
            .accessibilityHidden(true)
    }

    private var timeRegion: some View {
        VStack(alignment: .leading, spacing: ReminderStripStyle.lineSpacing) {
            Text(presentation.timeText)
                .font(ReminderStripStyle.timeFont)
                .foregroundStyle(ReminderStripStyle.primaryText)
            Text(presentation.dateText)
                .font(ReminderStripStyle.dateFont)
                .tracking(ReminderStripStyle.eyebrowTracking)
                .foregroundStyle(ReminderStripStyle.secondaryText)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(ReminderStripStyle.divider)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, ReminderStripStyle.lineSpacing)
            .accessibilityHidden(true)
    }

    private var eventContent: some View {
        VStack(alignment: .leading, spacing: ReminderStripStyle.lineSpacing) {
            Text(presentation.eyebrow)
                .font(ReminderStripStyle.eyebrowFont)
                .tracking(ReminderStripStyle.eyebrowTracking)
                .foregroundStyle(ReminderStripStyle.secondaryText)
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
        .font(.body)
        .fixedSize()
        .disabled(isPerformingAction)
    }

    @ViewBuilder
    private var actionControls: some View {
        if presentation.hasSource {
            quietButton("Open", accessibilityLabel: "Open reminder source", action: onOpen)
                .keyboardShortcut("o", modifiers: [.command])
        }
        Button("Snooze", action: onSnooze)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(minHeight: ReminderStripStyle.minimumActionHeight)
            .keyboardShortcut("s", modifiers: [.command])
            .accessibilityLabel("Snooze reminder for 10 minutes")
        quietButton("Dismiss", accessibilityLabel: "Dismiss reminder", action: onDismiss)
            .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            ReminderStripStyle.opaqueSurface
        } else {
            Rectangle().fill(.thickMaterial)
        }
    }

    /// Low-emphasis text control with a hit area large enough to click comfortably.
    private func quietButton(
        _ title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(ReminderStripStyle.secondaryText)
                .frame(minHeight: ReminderStripStyle.minimumActionHeight)
                .padding(.horizontal, ReminderStripStyle.actionSpacing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var borderColor: Color {
        colorSchemeContrast == .increased
            ? ReminderStripStyle.contrastBorder
            : ReminderStripStyle.border
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased
            ? ReminderStripStyle.contrastBorderWidth
            : ReminderStripStyle.borderWidth
    }
}
