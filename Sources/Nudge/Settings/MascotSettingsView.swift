import SwiftUI

/// The Bird tab.
struct MascotSettingsView: View {
    let controller: MascotController

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    BirdView(pose: BirdPose(isLookingAtViewer: true))
                        .frame(width: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Nudge bird")
                            .font(InkMetrics.titleFont)
                        Text("Walks on your Dock, delivers alerts, whistles, and talks trash.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Show the bird", isOn: binding(\.isEnabled))
            }

            if controller.settings.isEnabled {
                Section("Behavior") {
                    Toggle("Deliver alerts", isOn: binding(\.deliversAlerts))
                    Toggle("Drop by between alerts", isOn: binding(\.makesIdleVisits))
                    if controller.settings.makesIdleVisits {
                        Stepper(
                            "About every \(controller.settings.idleVisitIntervalMinutes) minutes",
                            value: binding(\.idleVisitIntervalMinutes),
                            in: MascotSettings.idleVisitIntervalRange,
                            step: 15
                        )
                    }
                    Toggle("Whistle", isOn: binding(\.whistles))
                    Text("Idle visits skip quiet hours (set under Tasks) and full-screen apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Attitude") {
                    Picker("Spice level", selection: binding(\.spice)) {
                        ForEach(MascotSettings.Spice.allCases) { spice in
                            Text(spice.label).tag(spice)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(controller.settings.spice.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(
                        "Add your own lines in ~/Library/Application Support/Nudge/MascotLines.json "
                            + "using the same categories as the bundled file."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Right now") {
                    HStack {
                        Button("Summon the Bird") { controller.summon() }
                        if controller.isMuted {
                            Button("Unmute") { controller.clearDoNotDisturb() }
                        } else {
                            Button("Mute for 1 Hour") { controller.muteForOneHour() }
                        }
                    }
                    if let until = controller.settings.doNotDisturbUntil, until > Date() {
                        Text("Muted until \(until.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let next = controller.nextIdleVisitDate {
                        Text("Next visit around \(next.formatted(date: .omitted, time: .shortened)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MascotSettings, Value>) -> Binding<Value> {
        Binding(
            get: { controller.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = controller.settings
                updated[keyPath: keyPath] = newValue
                controller.updateSettings(updated)
            }
        )
    }
}
