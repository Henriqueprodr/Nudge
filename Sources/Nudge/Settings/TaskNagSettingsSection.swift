import SwiftUI

/// Settings for smart task nags. There is deliberately no per-task setup.
struct TaskNagSettingsSection: View {
    let coordinator: TaskNagCoordinator

    var body: some View {
        Section {
            Toggle("Nag me about unfinished tasks", isOn: binding(\.isEnabled))
            if coordinator.settings.isEnabled {
                Toggle("Include tasks without a due date", isOn: binding(\.includesUndatedTasks))
                Picker("Quiet hours start", selection: binding(\.quietHoursStartHour)) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Quiet hours end", selection: binding(\.quietHoursEndHour)) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Stepper(
                    "At most \(coordinator.settings.dailyLimit) nags a day",
                    value: binding(\.dailyLimit),
                    in: TaskNagSettings.dailyLimitRange
                )
                Stepper(
                    "At least \(coordinator.settings.minimumGapMinutes) minutes apart",
                    value: binding(\.minimumGapMinutes),
                    in: TaskNagSettings.minimumGapRange,
                    step: 15
                )
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Task nags")
        } footer: {
            Text(
                "Nudge paces nags from each task's due date, how late it is, and its priority: "
                    + "due-today tasks at 11:00 and 16:00, overdue tasks every 4 hours, then every "
                    + "2 hours, then every 90 minutes after a week. Snooze, Not today, and Done "
                    + "work right from the alert. Nags use cached tasks only."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        let count = coordinator.outstandingTaskCount
        let tasks = count == 1 ? "1 task qualifies" : "\(count) tasks qualify"
        guard let next = coordinator.nextNagDate else {
            return count == 0 ? "Nothing to nag about right now." : "\(tasks); no nag is scheduled."
        }
        let when = next <= Date()
            ? "now"
            : next.formatted(date: .omitted, time: .shortened)
        return "\(tasks). Next nag: \(when)."
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TaskNagSettings, Value>) -> Binding<Value> {
        Binding(
            get: { coordinator.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = coordinator.settings
                updated[keyPath: keyPath] = newValue
                coordinator.updateSettings(updated)
            }
        )
    }
}
