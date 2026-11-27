import SwiftUI

/// Outlined, slightly wobbly buttons that press down onto their sticker shadow.
struct InkButtonStyle: ButtonStyle {
    enum Role: Sendable {
        /// Green fill: the action Nudge wants you to take.
        case primary
        /// Blue fill: brand actions such as Sign in.
        case brand
        /// Paper fill with an ink outline.
        case secondary
        /// Text only, for Dismiss-style escape hatches.
        case quiet
    }

    var role: Role = .secondary
    var minimumHeight: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(configuration: configuration, role: role, minimumHeight: minimumHeight)
    }
}

private struct InkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: InkButtonStyle.Role
    let minimumHeight: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(InkMetrics.headlineFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, role == .quiet ? 8 : 13)
            .frame(minHeight: minimumHeight)
            .background { background }
            .offset(y: pressOffset)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(InkShape(variant: .button))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }

    @ViewBuilder
    private var background: some View {
        switch role {
        case .quiet:
            InkShape(variant: .button)
                .fill(configuration.isPressed ? NudgePalette.ink.opacity(0.08) : .clear)
        case .primary, .brand, .secondary:
            ZStack {
                InkShape(variant: .button)
                    .fill(NudgePalette.stickerShadow)
                    .offset(y: configuration.isPressed ? 0 : 2)
                InkShape(variant: .button).fill(fill)
                InkShape(variant: .button)
                    .strokeBorderCompatible(NudgePalette.ink, lineWidth: InkMetrics.thinStrokeWidth)
            }
        }
    }

    private var pressOffset: CGFloat {
        guard role != .quiet, configuration.isPressed else { return 0 }
        return 2
    }

    private var fill: Color {
        switch role {
        case .primary:
            return NudgePalette.green
        case .brand:
            return NudgePalette.blue
        case .secondary, .quiet:
            return NudgePalette.paper
        }
    }

    private var foreground: Color {
        switch role {
        case .primary:
            return NudgePalette.onFill
        case .brand:
            return NudgePalette.onBlue
        case .secondary:
            return NudgePalette.ink
        case .quiet:
            return NudgePalette.inkSecondary
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static func ink(_ role: InkButtonStyle.Role = .secondary) -> InkButtonStyle {
        InkButtonStyle(role: role)
    }
}
