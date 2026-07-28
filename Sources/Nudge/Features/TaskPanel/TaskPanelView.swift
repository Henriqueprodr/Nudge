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
                }
                .buttonStyle(.plain)
                .help("Hide Task Panel")
                .accessibilityLabel("Hide task panel")

                Button(action: onToggleDisplayMode) {
                    Image(
                        systemName: store.state.displayMode == .compact
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left"
                    )
                }
                .buttonStyle(.plain)
                .help(store.state.displayMode == .compact ? "Expand Task Panel" : "Compact Task Panel")
                .accessibilityLabel(
                    store.state.displayMode == .compact ? "Expand task panel" : "Compact task panel"
                )
            }

            Divider()

            Group {
                if store.displayedTasks.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.displayedTasks) { task in
                                taskRow(task)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(
                                        priorityBackground(for: task),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
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
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(footerPresentation.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(footerPresentation.detail)
                .accessibilityLabel("\(footerPresentation.summary). \(footerPresentation.detail)")
        }
        .padding(18)
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    colorSchemeContrast == .increased
                        ? Color.primary.opacity(0.55)
                        : Color.white.opacity(0.18),
                    lineWidth: colorSchemeContrast == .increased ? 2 : 1
                )
        }
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
                } else {
                    Image(systemName: "circle")
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isCompleting(task))
            .help("Complete Task")
            .accessibilityLabel("Complete \(task.title)")
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                if let overrideText = localTimeOverrideText(for: task) {
                    Text(overrideText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                Image(systemName: "ellipsis.circle")
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
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(store.selectedTaskList == nil ? "No cached tasks" : "No incomplete tasks")
                .font(.subheadline.weight(.medium))

            Text(emptyStateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var panelBackground: AnyShapeStyle {
        if reduceTransparency || colorSchemeContrast == .increased {
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
        return AnyShapeStyle(.regularMaterial)
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

    private func priorityBackground(for task: TaskItem) -> Color {
        guard let hex = store.state.priorityPalette.colorHex(for: task.priority) else {
            return .clear
        }
        return TaskPriorityColor.color(hex: hex).opacity(
            colorSchemeContrast == .increased ? 0.32 : 0.20
        )
    }
}
