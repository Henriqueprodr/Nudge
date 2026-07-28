import Foundation
import Observation

@MainActor
@Observable
final class TaskPanelStore {
    private let taskRepository: any TaskRepository
    private let stateRepository: any TaskPanelStateRepository
    private let syncMetadataRepository: (any SyncMetadataRepository)?
    private var actionCoordinator: GoogleTasksActionCoordinator?
    private var snoozeWakeTask: Task<Void, Never>?
    private var referenceDate = Date()

    private(set) var tasks: [TaskItem] = []
    private(set) var taskLists: [TaskList] = []
    private(set) var state = TaskPanelState.defaultValue
    private(set) var syncMetadata = SyncMetadata.initial
    private(set) var persistenceErrorMessage: String?

    var displayedTasks: [TaskItem] {
        filteredTasks
    }

    var filteredTasks: [TaskItem] {
        tasks.filter { task in
            if let selectedTaskListID = state.selectedTaskListID,
               task.taskListID != selectedTaskListID {
                return false
            }
            guard let snoozedUntil = task.locallySnoozedUntil else {
                return true
            }
            return snoozedUntil <= referenceDate
        }
        .sorted(by: Self.taskSort)
    }

    var selectedTaskList: TaskList? {
        guard let selectedTaskListID = state.selectedTaskListID else {
            return nil
        }
        return taskLists.first { $0.id == selectedTaskListID }
    }

    init(
        taskRepository: any TaskRepository,
        stateRepository: any TaskPanelStateRepository,
        syncMetadataRepository: (any SyncMetadataRepository)? = nil
    ) {
        self.taskRepository = taskRepository
        self.stateRepository = stateRepository
        self.syncMetadataRepository = syncMetadataRepository
        restore()
    }

    func restore() {
        do {
            let restoredTasks = try taskRepository.fetchIncompleteTasks()
            let restoredTaskLists = try taskRepository.fetchTaskLists()
            var restoredState = try stateRepository.fetchState() ?? .defaultValue
            let restoredSyncMetadata = try syncMetadataRepository?.fetchMetadata() ?? .initial
            var didNormalizeState = false

            if let selectedTaskListID = restoredState.selectedTaskListID,
               !restoredTaskLists.contains(where: { $0.id == selectedTaskListID }) {
                restoredState.selectedTaskListID = nil
                didNormalizeState = true
            }

            let validatedOpacity = TaskPanelState.validatedOpacity(restoredState.opacity)
            let validatedTaskCount = TaskPanelState.validatedMaximumVisibleTaskCount(
                restoredState.maximumVisibleTaskCount
            )
            if restoredState.opacity != validatedOpacity
                || restoredState.maximumVisibleTaskCount != validatedTaskCount {
                restoredState.opacity = validatedOpacity
                restoredState.maximumVisibleTaskCount = validatedTaskCount
                didNormalizeState = true
            }

            tasks = restoredTasks
            taskLists = restoredTaskLists
            state = restoredState
            syncMetadata = restoredSyncMetadata
            persistenceErrorMessage = nil

            if didNormalizeState {
                persistState()
            }
            scheduleSnoozeWake()
        } catch {
            persistenceErrorMessage = "Cached tasks could not be loaded."
        }
    }

    func configureActions(_ actionCoordinator: GoogleTasksActionCoordinator) {
        self.actionCoordinator = actionCoordinator
    }

    func isCompleting(_ task: TaskItem) -> Bool {
        actionCoordinator?.activeTaskIDs.contains(task.id) == true
    }

    func complete(_ task: TaskItem) async {
        await actionCoordinator?.complete(task)
        restore()
    }

    func open(_ task: TaskItem) {
        actionCoordinator?.open(task)
    }

    func snooze(_ task: TaskItem, for interval: TimeInterval) {
        actionCoordinator?.snooze(task, until: Date().addingTimeInterval(interval))
        restore()
    }

    func setTimeOverride(_ task: TaskItem, hour: Int?, minute: Int?) {
        actionCoordinator?.setTimeOverride(task, hour: hour, minute: minute)
        restore()
    }

    var actionErrorMessage: String? {
        actionCoordinator?.errorMessage
    }

    func dismissActionError() {
        actionCoordinator?.clearError()
    }

    func setEnabled(_ isEnabled: Bool) {
        state.isEnabled = isEnabled
        persistState()
    }

    func setCorner(_ corner: ScreenCorner) {
        state.corner = corner
        state.placementMode = .anchored
        persistState()
    }

    func setPlacementMode(_ placementMode: TaskPanelState.PlacementMode) {
        state.placementMode = placementMode
        persistState()
    }

    func setDisplayMode(_ displayMode: TaskPanelState.DisplayMode) {
        state.displayMode = displayMode
        persistState()
    }

    func setScreenIdentifier(_ screenIdentifier: String?) {
        state.screenIdentifier = screenIdentifier
        persistState()
    }

    func setOpacity(_ opacity: Double) {
        state.opacity = TaskPanelState.validatedOpacity(opacity)
        persistState()
    }

    func setExpandedHeight(_ height: Double, persist: Bool = true) {
        state.expandedHeight = TaskPanelState.validatedExpandedHeight(height)
        state.displayMode = .expanded
        if persist {
            persistState()
        }
    }

    func setCustomPlacement(
        screenIdentifier: String,
        position: TaskPanelState.NormalizedPosition,
        persist: Bool = true
    ) {
        state.screenIdentifier = screenIdentifier
        state.placementMode = .custom
        state.normalizedPosition = position
        if persist {
            persistState()
        }
    }

    func resetPosition() {
        state.corner = .topTrailing
        state.placementMode = .anchored
        state.normalizedPosition = nil
        persistState()
    }

    func setPriorityPalette(_ palette: TaskPriorityPalette) {
        state.priorityPalette = palette
        persistState()
    }

    func setPriority(_ priority: TaskPriority, for task: TaskItem) {
        actionCoordinator?.setPriority(priority, for: task)
        restore()
    }

    func persistCurrentState() {
        persistState()
    }

    func prepareForSleep() {
        snoozeWakeTask?.cancel()
        snoozeWakeTask = nil
    }

    func recoverAfterLifecycleChange() {
        restore()
    }

    func selectTaskList(_ taskListID: String?) {
        let selectedTaskListID = taskListID.flatMap { candidate in
            taskLists.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        guard state.selectedTaskListID != selectedTaskListID else {
            return
        }
        state.selectedTaskListID = selectedTaskListID
        persistState()
    }

    private func persistState() {
        do {
            try stateRepository.save(state)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Task panel settings could not be saved."
        }
    }

    private static func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank < rhs.priority.sortRank
        }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func scheduleSnoozeWake() {
        snoozeWakeTask?.cancel()
        referenceDate = Date()
        guard let nextDate = tasks.compactMap(\.locallySnoozedUntil)
            .filter({ $0 > referenceDate })
            .min() else {
            return
        }
        let delay = nextDate.timeIntervalSince(referenceDate)
        snoozeWakeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.referenceDate = Date()
            self?.scheduleSnoozeWake()
        }
    }
}
