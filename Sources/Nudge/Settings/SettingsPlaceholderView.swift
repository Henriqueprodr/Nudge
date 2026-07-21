import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings arrive in a later phase",
            systemImage: "gearshape",
            description: Text("Phase 0 establishes only the application shell.")
        )
        .frame(width: 420, height: 220)
        .padding()
    }
}
