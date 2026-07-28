import AppKit
import SwiftData
import XCTest
@testable import Nudge

final class PhaseSixReliabilityTests: XCTestCase {
    @MainActor
    func testWakeAndSessionActivationCoalesceRecoveryAndIndependentRefreshes() async {
        let windows = TestLifecycleWindows()
        let calendar = TestLifecycleCalendar()
        let tasks = TestLifecycleTasks()
        let events = TestLifecycleEventProvider()
        let coordinator = ApplicationLifecycleCoordinator(
            windowCoordinator: windows,
            calendarCoordinator: calendar,
            tasksCoordinator: tasks,
            eventProvider: events
        )
        coordinator.start()
        defer { coordinator.stop() }

        events.emit(.willSleep)
        events.emit(.didWake)
        events.emit(.sessionBecameActive)
        await coordinator.flushPendingRecovery()

        XCTAssertEqual(windows.sleepPreparationCount, 1)
        XCTAssertEqual(windows.recoveryCount, 1)
        XCTAssertEqual(windows.sessionStates, [true])
        XCTAssertEqual(calendar.cacheRecoveryCount, 1)
        XCTAssertEqual(calendar.refreshTriggers, [.wake])
        XCTAssertEqual(tasks.refreshTriggers, [.wake])

        events.emit(.didWake)
        events.emit(.sessionBecameActive)
        await coordinator.flushPendingRecovery()
        XCTAssertEqual(calendar.refreshTriggers, [.wake])
        XCTAssertEqual(tasks.refreshTriggers, [.wake])

        events.emit(.willSleep)
        events.emit(.didWake)
        await coordinator.flushPendingRecovery()
        XCTAssertEqual(calendar.refreshTriggers, [.wake, .wake])
        XCTAssertEqual(tasks.refreshTriggers, [.wake, .wake])
    }

    @MainActor
    func testInactiveSessionDefersDirectOverlayUntilActivation() throws {
        let now = Date(timeIntervalSince1970: 60_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let window = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true }
        )
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: window,
            notificationFallback: TestNotificationFallback()
        )
        let reminder = makeReminder(identifier: "inactive", at: now, mode: .overlay)

        coordinator.setSessionActive(false)
        try coordinator.process([reminder])
        XCTAssertFalse(window.isVisible)

        coordinator.setSessionActive(true)
        XCTAssertTrue(window.isVisible)
        coordinator.dismissCurrentReminder()
    }

    @MainActor
    func testInactiveSessionUsesEnabledNotificationFallbackAndConfirmsDelivery() async throws {
        let now = Date(timeIntervalSince1970: 70_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let fallback = TestNotificationFallback(deliveryResult: true)
        let window = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: window,
            notificationFallback: fallback
        )
        let reminder = makeReminder(
            identifier: "fallback",
            at: now,
            mode: .overlayWithNotificationFallback
        )

        coordinator.setSessionActive(false)
        try coordinator.process([reminder])
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(fallback.deliveredIDs, [reminder.occurrenceID])
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(
                for: reminder.occurrenceID
            )?.state,
            .presented
        )
    }

    @MainActor
    func testPanelFallsBackWithoutDiscardingDisplayAndReanchorsOnReconnect() throws {
        let main = ScreenDescriptor(
            id: "main",
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852),
            isMain: true
        )
        let external = ScreenDescriptor(
            id: "external",
            name: "External",
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1040),
            isMain: false
        )
        let screens = TestScreenProvider(screens: [main])
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        try container.taskPanelStateRepository.save(
            TaskPanelState(
                isEnabled: true,
                displayMode: .compact,
                corner: .bottomTrailing,
                selectedTaskListID: nil,
                screenIdentifier: external.id
            )
        )
        let controller = TaskPanelWindowController(
            store: TaskPanelStore(
                taskRepository: container.taskRepository,
                stateRepository: container.taskPanelStateRepository
            ),
            screenProvider: screens
        )
        defer { controller.hide() }

        controller.restoreIfEnabled()
        XCTAssertEqual(
            controller.windowFrame,
            ScreenPlacement.cornerFrame(
                contentSize: CGSize(width: 346, height: 146),
                in: main.visibleFrame,
                corner: .bottomTrailing,
                edgeInset: 16
            )
        )
        XCTAssertEqual(controller.screenIdentifier, external.id)

        screens.screens = [main, external]
        controller.recoverAfterLifecycleChange()
        XCTAssertEqual(
            controller.windowFrame,
            ScreenPlacement.cornerFrame(
                contentSize: CGSize(width: 346, height: 146),
                in: external.visibleFrame,
                corner: .bottomTrailing,
                edgeInset: 16
            )
        )

        controller.setDisplayMode(.expanded)
        controller.setOpacity(0.65)
        XCTAssertEqual(controller.windowFrame?.size, CGSize(width: 346, height: 254))
        XCTAssertEqual(
            try container.taskPanelStateRepository.fetchState()?.displayMode,
            .expanded
        )
        XCTAssertEqual(try container.taskPanelStateRepository.fetchState()?.opacity, 0.65)

        let reconstructed = TaskPanelWindowController(
            store: TaskPanelStore(
                taskRepository: container.taskRepository,
                stateRepository: container.taskPanelStateRepository
            ),
            screenProvider: screens
        )
        XCTAssertEqual(reconstructed.opacity, 0.65)
    }

    @MainActor
    func testIndependentFullScreenPoliciesPersistOffByDefault() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let settings = TestPresentationSettingsRepository()
        var coordinator: WindowPresentationCoordinator? = WindowPresentationCoordinator(
            repositoryContainer: container,
            presentationSettingsRepository: settings,
            notificationFallback: TestNotificationFallback()
        )
        XCTAssertFalse(coordinator?.reminderOverFullScreen ?? true)
        XCTAssertFalse(coordinator?.taskPanelOverFullScreen ?? true)

        coordinator?.setReminderOverFullScreen(true)
        XCTAssertTrue(coordinator?.reminderOverFullScreen == true)
        XCTAssertFalse(coordinator?.taskPanelOverFullScreen ?? true)
        coordinator = nil

        let restored = WindowPresentationCoordinator(
            repositoryContainer: container,
            presentationSettingsRepository: settings,
            notificationFallback: TestNotificationFallback()
        )
        XCTAssertTrue(restored.reminderOverFullScreen)
        XCTAssertFalse(restored.taskPanelOverFullScreen)
    }

    @MainActor
    func testLaunchAtLoginStatusMappingAndFailureAreExplicit() {
        let cases: [(LaunchAtLoginServiceStatus, LaunchAtLoginManager.Status)] = [
            (.notRegistered, .notRegistered),
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.unavailable, .unavailable),
        ]
        for (serviceStatus, expected) in cases {
            let manager = LaunchAtLoginManager(
                service: TestLaunchAtLoginService(status: serviceStatus)
            )
            XCTAssertEqual(manager.status, expected)
        }

        let service = TestLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestFailure()
        let manager = LaunchAtLoginManager(service: service)
        manager.setEnabled(true)
        guard case .failed = manager.status else {
            return XCTFail("Registration failures must produce an explicit status.")
        }
    }

    @MainActor
    func testVersionOneStoreMigratesPanelCachesPendingActionAndTerminalDelivery() throws {
        let temporaryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("migration.store")
        let now = Date(timeIntervalSince1970: 80_000)
        let task = TaskItem(
            id: "task",
            taskListID: "list",
            title: "Cached task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        let occurrenceID = ReminderOccurrenceID(
            sourceKind: .calendar,
            sourceIdentifier: "terminal",
            occurrenceDate: now,
            revision: nil
        )
        let calendar = CalendarDescriptor(
            id: "calendar",
            title: "Cached calendar",
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: true,
            defaultReminders: []
        )
        let pendingAction = TaskPendingAction(
            id: UUID(),
            kind: .complete,
            taskID: task.id,
            taskListID: task.taskListID,
            originalTask: task,
            state: .pending,
            createdAt: now,
            updatedAt: now,
            failureMessage: nil
        )

        do {
            let schema = Schema(versionedSchema: NudgeSchemaV1.self)
            let configuration = ModelConfiguration("NudgeLocalCache", schema: schema, url: storeURL)
            let oldContainer = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(oldContainer)
            context.insert(NudgeSchemaV3.StoredTask(task: task))
            context.insert(StoredTaskList(taskList: TaskList(id: "list", title: "Inbox")))
            context.insert(
                StoredReminderDelivery(
                    record: ReminderDeliveryRecord(
                        occurrenceID: occurrenceID,
                        state: .acted,
                        scheduledAt: now,
                        presentedAt: now,
                        snoozedUntil: nil,
                        updatedAt: now
                    )
                )
            )
            context.insert(
                NudgeSchemaV1.StoredTaskPanelState(
                    isEnabled: true,
                    displayModeRawValue: TaskPanelState.DisplayMode.compact.rawValue,
                    cornerRawValue: ScreenCorner.bottomLeading.rawValue,
                    selectedTaskListIdentifier: "list"
                )
            )
            context.insert(try StoredTaskPendingAction(action: pendingAction))
            context.insert(
                StoredCalendarDescriptor(
                    identifier: calendar.id,
                    payload: try JSONEncoder().encode(calendar)
                )
            )
            try context.save()
        }

        let migrated = try LocalRepositoryContainer(storeURL: storeURL)
        XCTAssertEqual(try migrated.taskRepository.fetchIncompleteTasks(), [task])
        XCTAssertEqual(try migrated.taskPanelStateRepository.fetchState()?.displayMode, .compact)
        XCTAssertNil(try migrated.taskPanelStateRepository.fetchState()?.screenIdentifier)
        XCTAssertEqual(try migrated.taskPanelStateRepository.fetchState()?.opacity, 1)
        XCTAssertEqual(
            try migrated.taskPanelStateRepository.fetchState()?.maximumVisibleTaskCount,
            10
        )
        XCTAssertEqual(
            try migrated.reminderDeliveryRepository.deliveryRecord(for: occurrenceID)?.state,
            .acted
        )
        XCTAssertEqual(try migrated.taskPendingActionRepository.fetchActions(), [pendingAction])
        XCTAssertEqual(try migrated.calendarCacheRepository.fetchCalendars(), [calendar])
    }

    @MainActor
    func testVersionTwoPanelMigratesToVersionThreeDefaultsWithoutLosingScreen() throws {
        let temporaryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("version-two.store")

        do {
            let schema = Schema(versionedSchema: NudgeSchemaV2.self)
            let configuration = ModelConfiguration("NudgeLocalCache", schema: schema, url: storeURL)
            let oldContainer = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(oldContainer)
            context.insert(
                NudgeSchemaV2.StoredTaskPanelState(
                    isEnabled: true,
                    displayModeRawValue: TaskPanelState.DisplayMode.expanded.rawValue,
                    cornerRawValue: ScreenCorner.topLeading.rawValue,
                    selectedTaskListIdentifier: nil,
                    screenIdentifier: "preserved-screen"
                )
            )
            try context.save()
        }

        let migrated = try LocalRepositoryContainer(storeURL: storeURL)
        let state = try XCTUnwrap(migrated.taskPanelStateRepository.fetchState())

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.displayMode, .expanded)
        XCTAssertEqual(state.corner, .topLeading)
        XCTAssertEqual(state.screenIdentifier, "preserved-screen")
        XCTAssertEqual(state.opacity, 1)
        XCTAssertEqual(state.maximumVisibleTaskCount, 10)
    }

    @MainActor
    func testVersionThreeMigratesToVersionFourTaskAndPanelDefaults() throws {
        let temporaryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("version-three.store")
        let task = TaskItem(
            id: "legacy-v3-task",
            taskListID: "list",
            title: "Legacy V3 task",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
        let panelState = TaskPanelState(
            isEnabled: true,
            displayMode: .expanded,
            corner: .bottomTrailing,
            selectedTaskListID: "list",
            screenIdentifier: "preserved-screen",
            opacity: 0.8,
            maximumVisibleTaskCount: 12
        )

        do {
            let schema = Schema(versionedSchema: NudgeSchemaV3.self)
            let configuration = ModelConfiguration("NudgeLocalCache", schema: schema, url: storeURL)
            let oldContainer = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(oldContainer)
            context.insert(NudgeSchemaV3.StoredTask(task: task))
            context.insert(StoredTaskList(taskList: TaskList(id: "list", title: "Inbox")))
            context.insert(NudgeSchemaV3.StoredTaskPanelState(state: panelState))
            try context.save()
        }

        let migrated = try LocalRepositoryContainer(storeURL: storeURL)
        let migratedTask = try XCTUnwrap(
            migrated.taskRepository.fetchTask(identifier: task.id)
        )
        let migratedState = try XCTUnwrap(migrated.taskPanelStateRepository.fetchState())

        XCTAssertEqual(migratedTask.priority, .none)
        XCTAssertEqual(migratedState.corner, .bottomTrailing)
        XCTAssertEqual(migratedState.screenIdentifier, "preserved-screen")
        XCTAssertEqual(migratedState.expandedHeight, TaskPanelState.defaultExpandedHeight)
        XCTAssertEqual(migratedState.placementMode, .anchored)
        XCTAssertEqual(migratedState.priorityPalette, .defaultValue)
    }

    @MainActor
    func testCorruptStoreIsQuarantinedBeforeFreshPersistentStoreIsCreated() throws {
        let temporaryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let storeURL = temporaryRoot.appendingPathComponent("corrupt.store")
        let recoveryRoot = temporaryRoot.appendingPathComponent("Recovery")
        try Data("not a sqlite store".utf8).write(to: storeURL)
        try Data("sidecar".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))

        let result = LocalRepositoryContainer.openRecovering(
            storeURL: storeURL,
            recoveryRootURL: recoveryRoot
        )
        guard case let .recovered(folder) = result.recoveryStatus else {
            return XCTFail("A corrupt store should be quarantined before recovery.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(storeURL.lastPathComponent).path
            )
        )
        XCTAssertNotNil(result.recoveryStatus.message)
        XCTAssertEqual(try result.container.taskRepository.fetchIncompleteTasks(), [])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NudgePhaseSixTests-(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReminder(
        identifier: String,
        at date: Date,
        mode: Reminder.PresentationMode
    ) -> Reminder {
        Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: identifier,
                occurrenceDate: date,
                revision: nil
            ),
            title: "Reminder",
            detail: nil,
            triggerDate: date,
            expirationDate: nil,
            presentationMode: mode
        )
    }
}

@MainActor
private final class TestLifecycleEventProvider: ApplicationLifecycleEventProviding {
    private var handler: (@MainActor (ApplicationLifecycleCoordinator.Event) -> Void)?

    func start(handler: @escaping @MainActor (ApplicationLifecycleCoordinator.Event) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func emit(_ event: ApplicationLifecycleCoordinator.Event) {
        handler?(event)
    }
}

@MainActor
private final class TestLifecycleWindows: LifecycleWindowRecovering {
    private(set) var sleepPreparationCount = 0
    private(set) var recoveryCount = 0
    private(set) var sessionStates: [Bool] = []

    func prepareForSleep() { sleepPreparationCount += 1 }
    func setSessionActive(_ isActive: Bool) { sessionStates.append(isActive) }
    func recoverAfterLifecycleChange() { recoveryCount += 1 }
}

@MainActor
private final class TestLifecycleCalendar: LifecycleCalendarRecovering {
    private(set) var cacheRecoveryCount = 0
    private(set) var refreshTriggers: [GoogleCalendarRefreshTrigger] = []

    func recoverScheduleFromCache() { cacheRecoveryCount += 1 }
    func requestRefresh(_ trigger: GoogleCalendarRefreshTrigger) { refreshTriggers.append(trigger) }
}

@MainActor
private final class TestLifecycleTasks: LifecycleTasksRefreshing {
    private(set) var refreshTriggers: [GoogleTasksRefreshTrigger] = []

    func requestRefresh(_ trigger: GoogleTasksRefreshTrigger) { refreshTriggers.append(trigger) }
}

@MainActor
private final class TestScreenProvider: ScreenProviding {
    var screens: [ScreenDescriptor]

    init(screens: [ScreenDescriptor]) {
        self.screens = screens
    }

    var mainScreen: ScreenDescriptor? {
        screens.first(where: \.isMain) ?? screens.first
    }

    var pointerScreen: ScreenDescriptor? { mainScreen }
}

@MainActor
private final class TestNotificationFallback: ReminderNotificationFallbackProviding {
    private let authorizationResult: Bool
    private let deliveryResult: Bool
    private(set) var deliveredIDs: [ReminderOccurrenceID] = []
    var statusMessage = "Test notification fallback."

    init(authorizationResult: Bool = true, deliveryResult: Bool = false) {
        self.authorizationResult = authorizationResult
        self.deliveryResult = deliveryResult
    }

    func setSoundEnabled(_ isEnabled: Bool) {}

    func requestAuthorization() async -> Bool { authorizationResult }

    func deliver(_ reminder: Reminder) async -> Bool {
        deliveredIDs.append(reminder.occurrenceID)
        return deliveryResult
    }
}

private final class TestPresentationSettingsRepository: PresentationSettingsRepository {
    var storedSettings: PresentationSettings?

    func fetchSettings() -> PresentationSettings? { storedSettings }
    func save(_ settings: PresentationSettings) { storedSettings = settings }
}

@MainActor
private final class TestLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginServiceStatus
    var registerError: Error?

    init(status: LaunchAtLoginServiceStatus) {
        self.status = status
    }

    func register() throws {
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }

    func openSystemSettings() {}
}

private struct TestFailure: Error {}
