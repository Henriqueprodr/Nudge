import SwiftUI

struct TaskPanelView: View {
    let store: TaskPanelStore
    let onHide: () -> Void
    let onToggleDisplayMode: () -> Void
    let onResizeBegan: (TaskPanelResizeEdge) -> Void
    let onResizeChanged: (CGFloat) -> Void
    let onResizeEnded: () -> Void
    let footerNow: Date?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isMoveHandleHovered = false
    @State private var isMoveHandlePressed = false
    @State private var isResizeHandleHovered = false
    @State private var isResizeHandlePressed = false

    init(
        store: TaskPanelStore,
        onHide: @escaping () -> Void,
        onToggleDisplayMode: @escaping () -> Void,
        onResizeBegan: @escaping (TaskPanelResizeEdge) -> Void,
        onResizeChanged: @escaping (CGFloat) -> Void,
        onResizeEnded: @escaping () -> Void,
        footerNow: Date? = nil
    ) {
        self.store = store
        self.onHide = onHide
        self.onToggleDisplayMode = onToggleDisplayMode
        self.onResizeBegan = onResizeBegan
        self.onResizeChanged = onResizeChanged
        self.onResizeEnded = onResizeEnded
        self.footerNow = footerNow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                moveAffordance

                Picker("Google Tasks list", selection: selectedTaskListBinding) {
                    Text("All Lists")
                        .tag(nil as String?)

                    ForEach(store.taskLists) { taskList in
                        Text(taskList.title)
                            .lineLimit(1)
                            .tag(taskList.id as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Google Tasks list")

                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .buttonStyle(InkButtonStyle(role: .quiet, minimumHeight: 24))
                .help("Hide Task Panel")
                .accessibilityLabel("Hide task panel")

                Button(action: onToggleDisplayMode) {
                    Image(
                        systemName: store.state.displayMode == .compact
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left"
                    )
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .buttonStyle(InkButtonStyle(role: .quiet, minimumHeight: 24))
                .help(store.state.displayMode == .compact ? "Expand Task Panel" : "Compact Task Panel")
                .accessibilityLabel(
                    store.state.displayMode == .compact ? "Expand task panel" : "Compact task panel"
                )
            }

            WavyUnderline(amplitude: 1, wavelength: 10)
                .stroke(NudgePalette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(height: 4)
                .accessibilityHidden(true)

            Group {
                if store.displayedTasks.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(store.displayedTasks) { task in
                                taskRow(task)
                                    .padding(.leading, 12)
                                    .padding(.trailing, 4)
                                    .padding(.vertical, 6)
                                    .background(alignment: .leading) { priorityTab(for: task) }
                                    .accessibilityValue("\(task.priority.displayName) priority")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if let actionErrorMessage = store.actionErrorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Text(actionErrorMessage)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.dismissActionError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Task Message")
                    .accessibilityLabel("Dismiss task message")
                }
                .font(InkMetrics.captionFont)
                .foregroundStyle(NudgePalette.red)
            }

            Text(footerPresentation.summary)
                .font(InkMetrics.captionFont)
                .foregroundStyle(NudgePalette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(footerPresentation.detail)
                .accessibilityLabel("\(footerPresentation.summary). \(footerPresentation.detail)")
        }
        .padding(16)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .foregroundStyle(NudgePalette.ink)
        .background { InkCardBackground(variant: .panel) }
        .overlay(alignment: resizeEdge.overlayAlignment) {
            if store.state.displayMode == .expanded {
                ZStack {
                    TaskPanelResizeHandle(
                        onHoverChanged: { isResizeHandleHovered = $0 },
                        onDragBegan: {
                            isResizeHandlePressed = true
                            onResizeBegan(resizeEdge)
                        },
                        onDragChanged: onResizeChanged,
                        onDragEnded: {
                            isResizeHandlePressed = false
                            onResizeEnded()
                        }
                    )

                    Capsule()
                        .fill(resizeHandleColor)
                        .frame(
                            width: isResizeHandlePressed ? 38 : (isResizeHandleHovered ? 34 : 28),
                            height: isResizeHandleHovered || isResizeHandlePressed ? 4 : 3
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 14)
                .help("Drag Vertically to Resize Task Panel")
                .accessibilityLabel("Resize task panel vertically")
                .animation(.easeOut(duration: 0.12), value: isResizeHandleHovered)
                .animation(.easeOut(duration: 0.12), value: isResizeHandlePressed)
            }
        }
        .opacity(panelOpacity)
        .padding(8)
        .padding(.bottom, InkMetrics.stickerOffset)
    }

    @ViewBuilder
    private var moveAffordance: some View {
        if store.state.placementMode == .custom {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(moveHandleBackground)

                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(isMoveHandlePressed ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)

                TaskPanelDragHandle(
                    onHoverChanged: { isMoveHandleHovered = $0 },
                    onPressedChanged: { isMoveHandlePressed = $0 }
                )
            }
            .frame(width: 28, height: 24)
            .help("Drag to Move Task Panel")
            .accessibilityLabel("Move task panel")
            .animation(.easeOut(duration: 0.12), value: isMoveHandleHovered)
            .animation(.easeOut(duration: 0.12), value: isMoveHandlePressed)
        } else {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .help("Task Panel Position is Fixed")
                .accessibilityLabel("Task panel position is fixed")
        }
    }

    private var moveHandleBackground: Color {
        if isMoveHandlePressed {
            return Color.accentColor.opacity(0.22)
        }
        if isMoveHandleHovered {
            return Color.secondary.opacity(0.16)
        }
        return .clear
    }

    private var resizeHandleColor: Color {
        if isResizeHandlePressed {
            return Color.accentColor.opacity(0.9)
        }
        if isResizeHandleHovered {
            return Color.accentColor.opacity(0.65)
        }
        return Color.secondary.opacity(0.45)
    }

    @ViewBuilder
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task {
                    await store.complete(task)
                }
            } label: {
                if store.isCompleting(task) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    InkCheckbox(isChecked: false)
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isCompleting(task))
            .help("Complete Task")
            .accessibilityLabel("Complete \(task.title)")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(InkMetrics.bodyFont)
                    .foregroundStyle(NudgePalette.ink)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let badge = TaskDueBadge(dueDate: task.dueDate, now: footerNow ?? Date()) {
                        dueBadge(badge)
                    }
                    if let overrideText = localTimeOverrideText(for: task) {
                        Text(overrideText)
                            .font(InkMetrics.captionFont)
                            .foregroundStyle(NudgePalette.inkSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Menu("Priority") {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button {
                            store.setPriority(priority, for: task)
                        } label: {
                            if priority == task.priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                }

                Divider()

                Button("Open in Google Tasks") {
                    store.open(task)
                }
                .disabled(task.webViewURL == nil)

                Divider()

                Button("Snooze 1 Hour") {
                    store.snooze(task, for: 60 * 60)
                }
                Button("Snooze Until Tomorrow") {
                    store.snooze(task, for: 24 * 60 * 60)
                }

                Divider()

                Button("Use 9:00 AM") {
                    store.setTimeOverride(task, hour: 9, minute: 0)
                }
                Button("Use 12:00 PM") {
                    store.setTimeOverride(task, hour: 12, minute: 0)
                }
                Button("Clear Local Time") {
                    store.setTimeOverride(task, hour: nil, minute: nil)
                }
                .disabled(task.localTimeOverride == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(NudgePalette.inkSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var selectedTaskListBinding: Binding<String?> {
        Binding(
            get: {
                store.state.selectedTaskListID
            },
            set: { taskListID in
                store.selectTaskList(taskListID)
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            InkCheckbox(isChecked: true, size: 26)

            Text(store.selectedTaskList == nil ? "No cached tasks" : "All done here")
                .font(InkMetrics.headlineFont)

            Text(emptyStateDescription)
                .font(InkMetrics.captionFont)
                .foregroundStyle(NudgePalette.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateDescription: String {
        if let selectedTaskList = store.selectedTaskList {
            return "No incomplete cached tasks in \(selectedTaskList.title)."
        }
        return "Tasks cached by Nudge remain available offline."
    }

    private var footerPresentation: TaskPanelFooterPresentation {
        if let persistenceErrorMessage = store.persistenceErrorMessage {
            return TaskPanelFooterPresentation(
                summary: persistenceErrorMessage,
                detail: persistenceErrorMessage
            )
        }
        return TaskPanelFooterPresentation(
            taskCount: store.displayedTasks.count,
            metadata: store.syncMetadata,
            now: footerNow ?? Date()
        )
    }

    private func localTimeOverrideText(for task: TaskItem) -> String? {
        guard let localTimeOverride = task.localTimeOverride else {
            return nil
        }
        var components = DateComponents()
        components.hour = localTimeOverride.hour
        components.minute = localTimeOverride.minute
        guard let date = Calendar.current.date(from: components) else {
            return nil
        }
        return "Local time: \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var panelOpacity: Double {
        TaskPanelState.effectiveOpacity(
            store.state.opacity,
            accessibilityRequiresOpaqueSurface:
                reduceTransparency || colorSchemeContrast == .increased
        )
    }

    private var resizeEdge: TaskPanelResizeEdge {
        switch store.state.corner {
        case .topLeading, .topTrailing:
            .bottom
        case .bottomLeading, .bottomTrailing:
            .top
        }
    }

    /// A short ink-outlined tab in the priority colour along the row's leading edge.
    @ViewBuilder
    private func priorityTab(for task: TaskItem) -> some View {
        if let hex = store.state.priorityPalette.colorHex(for: task.priority) {
            ZStack {
                InkShape(variant: .chip).fill(TaskPriorityColor.color(hex: hex))
                InkShape(variant: .chip)
                    .strokeBorderCompatible(NudgePalette.ink, lineWidth: 1.5)
            }
            .frame(width: 6)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
        }
    }

    private func dueBadge(_ badge: TaskDueBadge) -> some View {
        let tint: Color = switch badge.kind {
        case .late: NudgePalette.red
        case .today: NudgePalette.green
        case .upcoming: NudgePalette.blue
        }
        return Text(badge.text)
            .font(.system(.caption2, design: .rounded).weight(.heavy))
            .foregroundStyle(badge.kind == .today ? NudgePalette.onFill : Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background {
                ZStack {
                    InkShape(variant: .chip).fill(tint)
                    InkShape(variant: .chip).strokeBorderCompatible(NudgePalette.ink, lineWidth: 1.2)
                }
            }
            .accessibilityLabel(badge.kind == .late ? "Overdue, \(badge.text)" : "Due \(badge.text)")
    }
}
