import SwiftUI

/// The Nudge logo and name at the top of the Account tab.
struct SettingsBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nudge")
                    .font(InkMetrics.titleFont)
                Text("Calendar alerts on screen. Tasks you can't ignore.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
