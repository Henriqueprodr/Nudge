import AppKit
import XCTest
@testable import Nudge

final class WindowPresentationTests: XCTestCase {
    @MainActor
    func testHidingTaskPanelDoesNotDismissReminderOverlay() throws {
        let repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let coordinator = WindowPresentationCoordinator(repositoryContainer: repositoryContainer)
        defer {
            coordinator.hideTaskPanel()
            coordinator.dismissTestReminder()
        }

        coordinator.showTestReminder()
        coordinator.showTaskPanel()

        XCTAssertTrue(coordinator.isReminderOverlayVisible)
        XCTAssertTrue(coordinator.isTaskPanelVisible)

        coordinator.hideTaskPanel()

        XCTAssertTrue(coordinator.isReminderOverlayVisible)
        XCTAssertFalse(coordinator.isTaskPanelVisible)
    }

    @MainActor
    func testSpecializedWindowsFloatAndOnlyBecomeKeyWhenInteractionRequiresIt() {
        let reminderWindow = ReminderOverlayWindow(contentRect: .zero)
        let taskWindow = TaskPanelWindow(contentRect: .zero)

        XCTAssertEqual(reminderWindow.level, .floating)
        XCTAssertEqual(taskWindow.level, .floating)
        XCTAssertGreaterThan(reminderWindow.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertGreaterThan(taskWindow.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertTrue(reminderWindow.canBecomeKey)
        XCTAssertTrue(taskWindow.canBecomeKey)
        XCTAssertFalse(reminderWindow.isKeyWindow)
        XCTAssertFalse(taskWindow.isKeyWindow)
        XCTAssertTrue(reminderWindow.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(taskWindow.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(reminderWindow.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(taskWindow.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(taskWindow.styleMask.contains(.resizable))
    }

    @MainActor
    func testTaskPanelResizeHandleForwardsPointerDragLifecycleAndScreenDelta() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 200, width: 346, height: 254),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let trackingView = TaskPanelResizeTrackingView(
            frame: CGRect(x: 0, y: 0, width: 346, height: 14)
        )
        window.contentView = trackingView
        var beginCount = 0
        var translations: [CGFloat] = []
        var endCount = 0
        var hoverValues: [Bool] = []
        trackingView.onHoverChanged = { hoverValues.append($0) }
        trackingView.onDragBegan = { beginCount += 1 }
        trackingView.onDragChanged = { translations.append($0) }
        trackingView.onDragEnded = { endCount += 1 }

        let pointerEvent = try taskPanelMouseEvent(
            type: .mouseMoved,
            location: CGPoint(x: 20, y: 10)
        )
        trackingView.mouseEntered(with: pointerEvent)
        trackingView.cursorUpdate(with: pointerEvent)
        XCTAssertEqual(NSCursor.current, .resizeUpDown)

        trackingView.mouseDown(
            with: try taskPanelMouseEvent(type: .leftMouseDown, location: CGPoint(x: 20, y: 10))
        )
        trackingView.mouseDragged(
            with: try taskPanelMouseEvent(type: .leftMouseDragged, location: CGPoint(x: 20, y: -70))
        )
        trackingView.mouseUp(
            with: try taskPanelMouseEvent(type: .leftMouseUp, location: CGPoint(x: 20, y: -70))
        )
        trackingView.mouseExited(with: pointerEvent)

        XCTAssertEqual(beginCount, 1)
        XCTAssertEqual(translations, [-80])
        XCTAssertEqual(endCount, 1)
        XCTAssertEqual(hoverValues, [true, false])
        XCTAssertFalse(trackingView.isDragging)
        XCTAssertEqual(NSCursor.current, .arrow)
    }

    @MainActor
    func testTaskPanelMoveHandleForwardsHoverAndPressedStateWithNativeCursors() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 200, width: 346, height: 254),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let draggingView = TaskPanelDraggingView(
            frame: CGRect(x: 0, y: 0, width: 28, height: 24)
        )
        window.contentView = draggingView
        var hoverValues: [Bool] = []
        var pressedValues: [Bool] = []
        var performedDragCount = 0
        draggingView.onHoverChanged = { hoverValues.append($0) }
        draggingView.onPressedChanged = { pressedValues.append($0) }
        draggingView.performWindowDrag = { _, _ in performedDragCount += 1 }

        let pointerEvent = try taskPanelMouseEvent(
            type: .mouseMoved,
            location: CGPoint(x: 14, y: 12)
        )
        draggingView.mouseEntered(with: pointerEvent)
        draggingView.cursorUpdate(with: pointerEvent)
        XCTAssertEqual(NSCursor.current, .openHand)

        draggingView.mouseDown(
            with: try taskPanelMouseEvent(
                type: .leftMouseDown,
                location: CGPoint(x: 14, y: 12)
            )
        )

        XCTAssertEqual(performedDragCount, 1)
        XCTAssertEqual(pressedValues, [true, false])
        XCTAssertFalse(draggingView.isPressed)
        draggingView.mouseExited(with: pointerEvent)
        XCTAssertEqual(hoverValues, [true, false])
        XCTAssertEqual(NSCursor.current, .arrow)
    }

    @MainActor
    func testFixedAndFreePlacementModesRestoreIndependentPositions() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let screen = taskPanelResizeScreen()
        let rememberedPosition = TaskPanelState.NormalizedPosition(x: 0.22, y: 0.41)
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        store.setExpandedHeight(360)
        store.setCustomPlacement(screenIdentifier: screen.id, position: rememberedPosition)
        let controller = TaskPanelWindowController(
            store: store,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { controller.hide() }
        controller.show()
        let freeFrame = try XCTUnwrap(controller.windowFrame)

        controller.setPlacementMode(.anchored)

        let fixedFrame = try XCTUnwrap(controller.windowFrame)
        XCTAssertEqual(store.state.placementMode, .anchored)
        XCTAssertEqual(store.state.normalizedPosition, rememberedPosition)
        XCTAssertEqual(fixedFrame.height, freeFrame.height)
        XCTAssertEqual(
            fixedFrame,
            ScreenPlacement.cornerFrame(
                contentSize: CGSize(width: 346, height: 360),
                in: screen.visibleFrame,
                corner: .topTrailing,
                edgeInset: 16
            )
        )

        controller.setPlacementMode(.custom)

        XCTAssertEqual(controller.windowFrame, freeFrame)
        XCTAssertEqual(store.state.placementMode, .custom)
        controller.panelWindow?.orderOut(nil)

        let restoredStore = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        let restoredController = TaskPanelWindowController(
            store: restoredStore,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { restoredController.hide() }
        restoredController.restoreIfEnabled()

        XCTAssertEqual(restoredStore.state.placementMode, .custom)
        XCTAssertEqual(restoredStore.state.normalizedPosition, rememberedPosition)
        XCTAssertEqual(restoredController.windowFrame, freeFrame)
    }

    @MainActor
    func testFixedPlacementRejectsWindowMovementAndCornerChangeKeepsFreePosition() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let screen = taskPanelResizeScreen()
        let rememberedPosition = TaskPanelState.NormalizedPosition(x: 0.15, y: 0.7)
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        store.setCustomPlacement(screenIdentifier: screen.id, position: rememberedPosition)
        let controller = TaskPanelWindowController(
            store: store,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { controller.hide() }
        controller.show()
        controller.corner = .bottomLeading
        let fixedFrame = try XCTUnwrap(controller.windowFrame)
        let window = try XCTUnwrap(controller.panelWindow)

        window.setFrameOrigin(CGPoint(x: fixedFrame.minX + 120, y: fixedFrame.minY + 80))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: window))

        XCTAssertEqual(controller.windowFrame, fixedFrame)
        XCTAssertEqual(store.state.placementMode, .anchored)
        XCTAssertEqual(store.state.corner, .bottomLeading)
        XCTAssertEqual(store.state.normalizedPosition, rememberedPosition)
    }

    @MainActor
    func testExplicitVerticalResizeKeepsConfiguredAnchorEdgeAndWidthFixed() throws {
        let screen = taskPanelResizeScreen()

        let topContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let topStore = TaskPanelStore(
            taskRepository: topContainer.taskRepository,
            stateRepository: topContainer.taskPanelStateRepository
        )
        topStore.setCorner(.topTrailing)
        let topController = TaskPanelWindowController(
            store: topStore,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { topController.hide() }
        topController.show()
        let topStart = try XCTUnwrap(topController.windowFrame)

        topController.beginVerticalResize(from: .bottom)
        topController.updateVerticalResize(screenTranslation: -90)
        topController.endVerticalResize()

        let topEnd = try XCTUnwrap(topController.windowFrame)
        XCTAssertEqual(topEnd.width, topStart.width)
        XCTAssertEqual(topEnd.height, topStart.height + 90)
        XCTAssertEqual(topEnd.maxY, topStart.maxY)
        XCTAssertEqual(topStore.state.expandedHeight, Double(topEnd.height))

        let bottomContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let bottomStore = TaskPanelStore(
            taskRepository: bottomContainer.taskRepository,
            stateRepository: bottomContainer.taskPanelStateRepository
        )
        bottomStore.setCorner(.bottomTrailing)
        let bottomController = TaskPanelWindowController(
            store: bottomStore,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { bottomController.hide() }
        bottomController.show()
        let bottomStart = try XCTUnwrap(bottomController.windowFrame)

        bottomController.beginVerticalResize(from: .top)
        bottomController.updateVerticalResize(screenTranslation: 90)
        bottomController.endVerticalResize()

        let bottomEnd = try XCTUnwrap(bottomController.windowFrame)
        XCTAssertEqual(bottomEnd.width, bottomStart.width)
        XCTAssertEqual(bottomEnd.height, bottomStart.height + 90)
        XCTAssertEqual(bottomEnd.minY, bottomStart.minY)
        XCTAssertEqual(bottomStore.state.expandedHeight, Double(bottomEnd.height))
    }

    @MainActor
    func testVerticalResizeClampsToVisibleFrameAndCompactRemainsFixed() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let screen = taskPanelResizeScreen()
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        store.setExpandedHeight(350)
        let controller = TaskPanelWindowController(
            store: store,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { controller.hide() }
        controller.show()

        controller.beginVerticalResize(from: .bottom)
        controller.updateVerticalResize(screenTranslation: 2_000)
        controller.endVerticalResize()
        XCTAssertEqual(controller.windowFrame?.height, TaskPanelWindowController.compactHeight)

        controller.beginVerticalResize(from: .bottom)
        controller.updateVerticalResize(screenTranslation: -2_000)
        controller.endVerticalResize()
        let maximumHeight = screen.visibleFrame.height - TaskPanelWindowController.edgeInset * 2
        XCTAssertEqual(controller.windowFrame?.height, maximumHeight)
        XCTAssertTrue(screen.visibleFrame.contains(try XCTUnwrap(controller.windowFrame)))

        controller.setDisplayMode(.compact)
        XCTAssertEqual(controller.windowFrame?.height, TaskPanelWindowController.compactHeight)
        XCTAssertEqual(controller.windowMinimumSize?.height, TaskPanelWindowController.compactHeight)
        XCTAssertEqual(controller.windowMaximumSize?.height, TaskPanelWindowController.compactHeight)
        let compactFrame = try XCTUnwrap(controller.windowFrame)

        controller.beginVerticalResize(from: .bottom)
        controller.updateVerticalResize(screenTranslation: -100)
        controller.endVerticalResize()
        XCTAssertEqual(controller.windowFrame, compactFrame)

        controller.setDisplayMode(.expanded)
        XCTAssertEqual(controller.windowFrame?.height, maximumHeight)
        XCTAssertEqual(controller.windowMinimumSize?.width, controller.windowMaximumSize?.width)
        XCTAssertEqual(controller.windowMaximumSize?.height, maximumHeight)
    }

    @MainActor
    func testCustomResizePersistsHeightAndNormalizedPositionAcrossControllerRecreation() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let screen = taskPanelResizeScreen()
        let firstStore = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        firstStore.setExpandedHeight(300)
        firstStore.setCustomPlacement(
            screenIdentifier: screen.id,
            position: TaskPanelState.NormalizedPosition(x: 0.25, y: 0.55)
        )
        let firstController = TaskPanelWindowController(
            store: firstStore,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        firstController.show()
        let startingFrame = try XCTUnwrap(firstController.windowFrame)

        firstController.beginVerticalResize(from: .bottom)
        firstController.updateVerticalResize(screenTranslation: -80)
        firstController.endVerticalResize()
        let resizedFrame = try XCTUnwrap(firstController.windowFrame)
        XCTAssertEqual(resizedFrame.maxY, startingFrame.maxY)
        XCTAssertEqual(firstStore.state.placementMode, .custom)
        XCTAssertEqual(firstStore.state.expandedHeight, 380)
        firstController.hide()

        let restoredStore = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        let restoredController = TaskPanelWindowController(
            store: restoredStore,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { restoredController.hide() }
        restoredController.show()
        let restoredFrame = try XCTUnwrap(restoredController.windowFrame)

        XCTAssertEqual(restoredStore.state.placementMode, .custom)
        XCTAssertEqual(restoredStore.state.expandedHeight, 380)
        XCTAssertEqual(restoredFrame.minX, resizedFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restoredFrame.minY, resizedFrame.minY, accuracy: 0.001)
        XCTAssertEqual(restoredFrame.width, resizedFrame.width, accuracy: 0.001)
        XCTAssertEqual(restoredFrame.height, resizedFrame.height, accuracy: 0.001)
    }

    @MainActor
    func testFullScreenBehaviorIsExplicitAndOffByDefault() throws {
        let repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let reminderController = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let taskController = TaskPanelWindowController(
            store: TaskPanelStore(
                taskRepository: repositoryContainer.taskRepository,
                stateRepository: repositoryContainer.taskPanelStateRepository
            )
        )

        XCTAssertFalse(reminderController.presentsOverFullScreenApplications)
        XCTAssertFalse(taskController.presentsOverFullScreenApplications)

        reminderController.presentsOverFullScreenApplications = true
        taskController.presentsOverFullScreenApplications = true

        XCTAssertTrue(reminderController.presentsOverFullScreenApplications)
        XCTAssertTrue(taskController.presentsOverFullScreenApplications)
    }

    @MainActor
    func testReminderAndPanelKeepIndependentSpacesPoliciesWhileBothStayVisible() throws {
        let repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let reminderController = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true },
            sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) }
        )
        let taskController = TaskPanelWindowController(
            store: TaskPanelStore(
                taskRepository: repositoryContainer.taskRepository,
                stateRepository: repositoryContainer.taskPanelStateRepository
            )
        )
        defer {
            reminderController.dismiss()
            taskController.hide()
        }

        reminderController.joinsAllSpaces = false
        reminderController.presentsOverFullScreenApplications = true
        taskController.joinsAllSpaces = true
        taskController.presentsOverFullScreenApplications = false
        taskController.show()
        reminderController.present(
            phaseSevenReminder(id: "spaces"),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        XCTAssertTrue(taskController.isVisible)
        XCTAssertTrue(reminderController.isVisible)
        XCTAssertFalse(
            reminderController.windowCollectionBehavior?.contains(.canJoinAllSpaces) ?? true
        )
        XCTAssertTrue(
            reminderController.windowCollectionBehavior?.contains(.fullScreenAuxiliary) == true
        )
        XCTAssertTrue(
            taskController.windowCollectionBehavior?.contains(.canJoinAllSpaces) == true
        )
        XCTAssertFalse(
            taskController.windowCollectionBehavior?.contains(.fullScreenAuxiliary) ?? true
        )
    }

    func testValidatedPhaseSevenSettingsUseDocumentedBoundsAndDefaults() throws {
        XCTAssertEqual(ReminderPresentationDuration(seconds: 1).seconds, 3)
        XCTAssertEqual(ReminderPresentationDuration(seconds: 10).seconds, 10)
        XCTAssertEqual(ReminderPresentationDuration(seconds: 90).seconds, 30)
        XCTAssertEqual(PeriodicRefreshInterval(minutes: 1).minutes, 5)
        XCTAssertEqual(PeriodicRefreshInterval(minutes: 5).minutes, 5)
        XCTAssertEqual(PeriodicRefreshInterval(minutes: 90).minutes, 60)
        XCTAssertEqual(TaskPanelState.validatedOpacity(0.2), 0.65)
        XCTAssertEqual(TaskPanelState.validatedOpacity(2), 1)
        XCTAssertEqual(
            TaskPanelState.effectiveOpacity(0.65, accessibilityRequiresOpaqueSurface: true),
            1
        )
        XCTAssertEqual(
            TaskPanelState.effectiveOpacity(0.65, accessibilityRequiresOpaqueSurface: false),
            0.65
        )
        XCTAssertEqual(TaskPanelState.validatedMaximumVisibleTaskCount(0), 1)
        XCTAssertEqual(TaskPanelState.validatedMaximumVisibleTaskCount(50), 25)
        XCTAssertEqual(TaskPanelState.validatedExpandedHeight(20), 146)
        XCTAssertEqual(TaskPanelState.validatedExpandedHeight(9_000), 4_000)

        let legacy = LegacyPresentationSettings(
            schemaVersion: 1,
            reminderDisplayTarget: .fixed("legacy-display"),
            reminderOverFullScreen: true,
            taskPanelOverFullScreen: false
        )
        let decoded = try JSONDecoder().decode(
            PresentationSettings.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.reminderDisplayTarget, .fixed("legacy-display"))
        XCTAssertEqual(decoded.reminderDuration, .defaultValue)
        XCTAssertEqual(decoded.schemaVersion, PresentationSettings.currentSchemaVersion)
        XCTAssertFalse(decoded.remindersPersistUntilAction)
        XCTAssertFalse(PresentationSettings.defaultValue.remindersPersistUntilAction)
        XCTAssertEqual(decoded.reminderSound, .hero)
        XCTAssertEqual(PresentationSettings.defaultValue.reminderSound, .hero)
        XCTAssertTrue(decoded.remindersJoinAllSpaces)
        XCTAssertTrue(decoded.taskPanelJoinsAllSpaces)
        XCTAssertFalse(decoded.showsDockIcon)

        let explicitlyPersistent = LegacyPresentationSettingsWithPersistence(
            schemaVersion: 2,
            reminderDisplayTarget: .pointer,
            remindersPersistUntilAction: true,
            reminderOverFullScreen: false,
            taskPanelOverFullScreen: false
        )
        let persistentDecoded = try JSONDecoder().decode(
            PresentationSettings.self,
            from: JSONEncoder().encode(explicitlyPersistent)
        )
        XCTAssertTrue(persistentDecoded.remindersPersistUntilAction)

        XCTAssertEqual(
            ReminderSound.allCases,
            [.off, .hero, .bottle, .morse, .sosumi]
        )
        for sound in ReminderSound.allCases {
            let decodedSound = try JSONDecoder().decode(
                ReminderSound.self,
                from: JSONEncoder().encode(sound)
            )
            XCTAssertEqual(decodedSound, sound)
        }
        let roundTripped = try JSONDecoder().decode(
            PresentationSettings.self,
            from: JSONEncoder().encode(PresentationSettings.defaultValue)
        )
        XCTAssertEqual(roundTripped.schemaVersion, 5)
        XCTAssertEqual(roundTripped.reminderSound, .hero)
    }

    func testTaskPanelFooterIsConciseForCurrentCachedAndNeverSynchronizedStates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let current = TaskPanelFooterPresentation(
            taskCount: 19,
            metadata: SyncMetadata(
                status: .current,
                lastAttemptAt: now,
                lastSuccessfulRefreshAt: now.addingTimeInterval(-5 * 60),
                statusMessage: "Up to date"
            ),
            now: now
        )
        let cached = TaskPanelFooterPresentation(
            taskCount: 1,
            metadata: SyncMetadata(
                status: .failed,
                lastAttemptAt: now,
                lastSuccessfulRefreshAt: now.addingTimeInterval(-2 * 60 * 60),
                statusMessage: "Authentication required"
            ),
            now: now
        )
        let never = TaskPanelFooterPresentation(
            taskCount: 0,
            metadata: .initial,
            now: now
        )

        XCTAssertEqual(current.summary, "19 tasks · Updated 5m ago")
        XCTAssertTrue(current.detail.contains("Up to date"))
        XCTAssertEqual(cached.summary, "1 task · Cached 2h ago")
        XCTAssertTrue(cached.detail.contains("Authentication required"))
        XCTAssertEqual(never.summary, "0 tasks · Not synced")
    }

    @MainActor
    func testResetTaskPanelPositionPreservesDisplayAndExpandedHeight() throws {
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let screen = ScreenDescriptor(
            id: "display",
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 24, width: 1200, height: 776),
            isMain: true
        )
        let store = TaskPanelStore(
            taskRepository: container.taskRepository,
            stateRepository: container.taskPanelStateRepository
        )
        store.setScreenIdentifier(screen.id)
        store.setExpandedHeight(400)
        store.setCustomPlacement(
            screenIdentifier: screen.id,
            position: TaskPanelState.NormalizedPosition(x: 0.2, y: 0.3)
        )
        let controller = TaskPanelWindowController(
            store: store,
            screenProvider: PhaseSevenScreenProvider(screen: screen)
        )
        defer { controller.hide() }

        controller.show()
        controller.resetPosition()

        XCTAssertEqual(store.state.placementMode, .anchored)
        XCTAssertEqual(store.state.corner, .topTrailing)
        XCTAssertNil(store.state.normalizedPosition)
        XCTAssertEqual(store.state.screenIdentifier, screen.id)
        XCTAssertEqual(store.state.expandedHeight, 400)
        XCTAssertEqual(
            controller.windowFrame,
            ScreenPlacement.cornerFrame(
                contentSize: CGSize(width: 346, height: 400),
                in: screen.visibleFrame,
                corner: .topTrailing,
                edgeInset: 16
            )
        )
    }

    func testSchemaFourReminderSoundsMigrateWithoutLosingOff() throws {
        let removedAudibleValues = ["ping", "pop", "glass", "tink", "purr"]
        for removedValue in removedAudibleValues {
            let decoded = try JSONDecoder().decode(
                PresentationSettings.self,
                from: JSONEncoder().encode(
                    LegacyPresentationSettingsWithSound(
                        schemaVersion: 4,
                        reminderSound: removedValue
                    )
                )
            )

            XCTAssertEqual(decoded.schemaVersion, 5)
            XCTAssertEqual(decoded.reminderSound, .hero)
        }

        let off = try JSONDecoder().decode(
            PresentationSettings.self,
            from: JSONEncoder().encode(
                LegacyPresentationSettingsWithSound(schemaVersion: 4, reminderSound: "off")
            )
        )
        XCTAssertEqual(off.schemaVersion, 5)
        XCTAssertEqual(off.reminderSound, .off)
    }

    func testAudibleReminderSoundsResolveThroughNSSound() throws {
        for sound in ReminderSound.allCases where sound.isEnabled {
            let systemSoundName = try XCTUnwrap(sound.systemSoundName)
            XCTAssertNotNil(
                NSSound(named: NSSound.Name(systemSoundName)),
                "Expected native macOS sound named \(systemSoundName)"
            )
        }
    }

    @MainActor
    func testReminderSoundSettingPersistsPreviewsAndTurnsAllReminderAudioOff() throws {
        let repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let settingsRepository = PhaseSevenPresentationSettingsRepository()
        let soundPlayer = RecordingReminderSoundPlayer()
        let notificationFallback = RecordingReminderNotificationFallback()
        let coordinator = WindowPresentationCoordinator(
            repositoryContainer: repositoryContainer,
            presentationSettingsRepository: settingsRepository,
            notificationFallback: notificationFallback,
            soundPlayer: soundPlayer
        )

        XCTAssertEqual(coordinator.reminderSound, .hero)
        XCTAssertEqual(notificationFallback.soundEnabledValues, [true])

        coordinator.setReminderSound(.bottle)

        XCTAssertEqual(coordinator.reminderSound, .bottle)
        XCTAssertEqual(settingsRepository.storedSettings?.reminderSound, .bottle)
        XCTAssertEqual(soundPlayer.playedSounds, [.bottle])
        XCTAssertEqual(notificationFallback.soundEnabledValues, [true, true])

        coordinator.setReminderSound(.off)

        XCTAssertEqual(coordinator.reminderSound, .off)
        XCTAssertEqual(settingsRepository.storedSettings?.reminderSound, .off)
        XCTAssertEqual(soundPlayer.playedSounds, [.bottle])
        XCTAssertEqual(soundPlayer.stopCount, 1)
        XCTAssertEqual(notificationFallback.soundEnabledValues, [true, true, false])
    }

    @MainActor
    func testNotificationFallbackOmitsSoundWhenReminderSoundIsOff() {
        let fallback = ReminderNotificationFallback()

        fallback.setSoundEnabled(true)
        XCTAssertNotNil(fallback.notificationSound)
        XCTAssertEqual(fallback.foregroundPresentationOptions, [.banner, .sound])
        XCTAssertEqual(fallback.authorizationOptions, [.alert, .sound])

        fallback.setSoundEnabled(false)
        XCTAssertNil(fallback.notificationSound)
        XCTAssertEqual(fallback.foregroundPresentationOptions, [.banner])
        XCTAssertEqual(fallback.authorizationOptions, [.alert])
    }

    @MainActor
    func testControlStripIsMeasuredAndRestsInsideUpperCenterOfVisibleFrame() {
        var animatedFrames: [CGRect] = []
        var animationDurations: [TimeInterval] = []
        let screen = ScreenDescriptor(
            id: "screen",
            name: "Screen",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852),
            isMain: true
        )
        let controller = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            screenProvider: PhaseSevenScreenProvider(screen: screen),
            presentationAvailability: { _ in true },
            reduceMotion: { true },
            sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) },
            alphaAnimator: { window, endAlpha, duration in
                animatedFrames.append(window.frame)
                animationDurations.append(duration)
                window.alphaValue = endAlpha
            }
        )
        defer { controller.dismiss() }

        controller.present(
            phaseSevenReminder(id: "strip"),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        let frame = try? XCTUnwrap(controller.windowFrame)
        guard let frame else { return }
        XCTAssertTrue(screen.visibleFrame.contains(frame))
        XCTAssertEqual(frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, screen.visibleFrame.maxY - 8, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.width, ReminderStripStyle.minimumWidth)
        XCTAssertLessThanOrEqual(frame.width, ReminderStripStyle.maximumWidth)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertLessThan(frame.height, frame.width, "The strip must stay horizontal")
        XCTAssertEqual(animatedFrames, [frame])
        XCTAssertEqual(animationDurations, [ReminderStripStyle.reducedMotionDuration])
        XCTAssertEqual(ReminderStripStyle.transitionScale, 0.94)
    }

    @MainActor
    func testPopEntranceAndTimedExitFadeAtTheSameRestingFrame() async {
        let store = ReminderOverlayStore()
        let dismissed = expectation(description: "Timed pop-out completed")
        var animatedFrames: [CGRect] = []
        var targetAlphas: [CGFloat] = []
        var animationDurations: [TimeInterval] = []
        let controller = ReminderOverlayWindowController(
            store: store,
            presentationAvailability: { _ in true },
            reduceMotion: { false },
            sleeper: { _ in await Task.yield() },
            alphaAnimator: { window, endAlpha, duration in
                animatedFrames.append(window.frame)
                targetAlphas.append(endAlpha)
                animationDurations.append(duration)
                window.alphaValue = endAlpha
            }
        )
        defer { controller.dismiss() }
        controller.persistsUntilAction = false

        controller.present(
            phaseSevenReminder(id: "pop-in-place"),
            onDismiss: { dismissed.fulfill() },
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        await fulfillment(of: [dismissed], timeout: 1)

        XCTAssertEqual(animatedFrames.count, 2)
        XCTAssertEqual(animatedFrames.first, animatedFrames.last)
        XCTAssertEqual(targetAlphas, [1, 0])
        XCTAssertEqual(
            animationDurations,
            [ReminderStripStyle.entryDuration, ReminderStripStyle.exitDuration]
        )
        XCTAssertTrue(store.isAnimatingOut)
    }

    @MainActor
    func testLongEventContentWidensTheStripOnlyUpToTheDocumentedMaximum() {
        let screen = ScreenDescriptor(
            id: "screen",
            name: "Screen",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1440, height: 852),
            isMain: true
        )
        let shortController = phaseSevenStripController(screen: screen)
        let longController = phaseSevenStripController(screen: screen)
        defer {
            shortController.dismiss()
            longController.dismiss()
        }

        shortController.present(
            phaseSevenReminder(id: "short", title: "Standup"),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )
        longController.present(
            phaseSevenReminder(
                id: "long",
                title: String(repeating: "Quarterly planning workshop ", count: 6)
            ),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        guard let shortFrame = shortController.windowFrame,
              let longFrame = longController.windowFrame else {
            return XCTFail("Both presentations must produce a measured frame")
        }
        let maximumWidth = ReminderStripStyle.maximumWidth
        XCTAssertGreaterThan(longFrame.width, shortFrame.width)
        XCTAssertEqual(longFrame.width, maximumWidth, accuracy: 0.5)
        XCTAssertTrue(screen.visibleFrame.contains(longFrame))
    }

    @MainActor
    func testEnlargedControlStripClampsToANarrowDisplay() {
        let screen = ScreenDescriptor(
            id: "narrow-screen",
            name: "Narrow Screen",
            frame: CGRect(x: 0, y: 0, width: 520, height: 700),
            visibleFrame: CGRect(x: 0, y: 24, width: 520, height: 652),
            isMain: true
        )
        let controller = phaseSevenStripController(screen: screen)
        defer { controller.dismiss() }

        controller.present(
            phaseSevenReminder(
                id: "narrow-strip",
                title: String(repeating: "Quarterly planning workshop ", count: 6)
            ),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        guard let frame = controller.windowFrame else {
            return XCTFail("The narrow display must produce a measured frame")
        }
        let expectedWidth = screen.visibleFrame.width
            - ReminderStripStyle.screenHorizontalInset * 2
        XCTAssertEqual(frame.width, expectedWidth, accuracy: 0.5)
        XCTAssertEqual(frame.midX, screen.visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(
            frame.maxY,
            screen.visibleFrame.maxY - ReminderStripStyle.screenTopInset,
            accuracy: 0.5
        )
        XCTAssertTrue(screen.visibleFrame.contains(frame))
        XCTAssertLessThan(frame.height, frame.width)
    }

    @MainActor
    func testCancellationBeforeTimedExitKeepsTheReminderUndismissed() async {
        let dismissed = expectation(description: "Cancelled timer must not dismiss")
        dismissed.isInverted = true
        let controller = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true },
            reduceMotion: { false },
            sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) }
        )
        controller.persistsUntilAction = false
        controller.present(
            phaseSevenReminder(id: "cancelled"),
            onDismiss: { dismissed.fulfill() },
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        XCTAssertTrue(controller.isVisible)
        controller.dismiss()
        await fulfillment(of: [dismissed], timeout: 0.05)
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testPersistentReminderIsNotDismissedByTheDurationTimer() async {
        let dismissed = expectation(description: "Persistent reminder must wait for an action")
        dismissed.isInverted = true
        let controller = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true },
            reduceMotion: { false },
            sleeper: { _ in await Task.yield() }
        )
        controller.persistsUntilAction = true
        controller.present(
            phaseSevenReminder(id: "persistent"),
            onDismiss: { dismissed.fulfill() },
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )
        for _ in 0..<10 { await Task.yield() }

        await fulfillment(of: [dismissed], timeout: 0.05)
        XCTAssertTrue(controller.isVisible)
        controller.dismiss()
    }

    @MainActor
    func testBeginningAnActionCancelsTimedExpiry() async {
        let dismissed = expectation(description: "An action must cancel timed expiry")
        dismissed.isInverted = true
        let controller = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true },
            reduceMotion: { false },
            sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) }
        )
        controller.persistsUntilAction = false
        controller.present(
            phaseSevenReminder(id: "action-cancels-timer"),
            onDismiss: { dismissed.fulfill() },
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )

        controller.beginAction()

        await fulfillment(of: [dismissed], timeout: 0.05)
        XCTAssertTrue(controller.isVisible)
        controller.endAction(errorMessage: "This reminder could not be snoozed.")
        XCTAssertTrue(controller.isVisible)
        controller.dismiss()
    }

    @MainActor
    func testTimedReminderDismissesAndLatePresentationCallbackIsIgnored() async {
        let dismissed = expectation(description: "Timed reminder dismissed")
        let controller = ReminderOverlayWindowController(
            store: ReminderOverlayStore(),
            presentationAvailability: { _ in true },
            reduceMotion: { false },
            sleeper: { _ in await Task.yield() }
        )
        controller.persistsUntilAction = false
        controller.presentationDuration = ReminderPresentationDuration(seconds: 3)
        controller.present(
            phaseSevenReminder(id: "timed"),
            onDismiss: { dismissed.fulfill() },
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in }
        )
        await fulfillment(of: [dismissed], timeout: 1)
        controller.dismiss()

        var callbackIDs: [String] = []
        controller.persistsUntilAction = true
        controller.present(
            phaseSevenReminder(id: "old"),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in callbackIDs.append("old") }
        )
        controller.present(
            phaseSevenReminder(id: "new"),
            onDismiss: {},
            onSnooze: {},
            onOpen: {},
            onPresentationResult: { _ in callbackIDs.append("new") }
        )
        await Task.yield()

        XCTAssertEqual(callbackIDs, ["new"])
        controller.dismiss()
    }

    @MainActor
    func testDockPolicyMappingPersistsOnlySuccessfulChanges() throws {
        let repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let settingsRepository = PhaseSevenPresentationSettingsRepository()
        let activationPolicy = PhaseSevenActivationPolicyAdapter()
        let coordinator = WindowPresentationCoordinator(
            repositoryContainer: repositoryContainer,
            presentationSettingsRepository: settingsRepository,
            activationPolicyAdapter: activationPolicy
        )

        XCTAssertTrue(coordinator.setShowsDockIcon(true))
        XCTAssertEqual(activationPolicy.requestedVisibility, [true])
        XCTAssertEqual(settingsRepository.storedSettings?.showsDockIcon, true)

        activationPolicy.shouldSucceed = false
        XCTAssertFalse(coordinator.setShowsDockIcon(false))
        XCTAssertEqual(settingsRepository.storedSettings?.showsDockIcon, true)
    }

}

private struct LegacyPresentationSettings: Codable {
    let schemaVersion: Int
    let reminderDisplayTarget: PresentationSettings.ReminderDisplayTarget
    let reminderOverFullScreen: Bool
    let taskPanelOverFullScreen: Bool
}

private struct LegacyPresentationSettingsWithPersistence: Codable {
    let schemaVersion: Int
    let reminderDisplayTarget: PresentationSettings.ReminderDisplayTarget
    let remindersPersistUntilAction: Bool
    let reminderOverFullScreen: Bool
    let taskPanelOverFullScreen: Bool
}

private struct LegacyPresentationSettingsWithSound: Codable {
    let schemaVersion: Int
    let reminderSound: String
}

private func taskPanelMouseEvent(type: NSEvent.EventType, location: CGPoint) throws -> NSEvent {
    try XCTUnwrap(
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
    )
}

private func taskPanelResizeScreen() -> ScreenDescriptor {
    ScreenDescriptor(
        id: "resize-display",
        name: "Resize Display",
        frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
        visibleFrame: CGRect(x: 0, y: 24, width: 1_200, height: 776),
        isMain: true
    )
}

@MainActor
private final class PhaseSevenScreenProvider: ScreenProviding {
    let screens: [ScreenDescriptor]

    init(screen: ScreenDescriptor) {
        screens = [screen]
    }

    var mainScreen: ScreenDescriptor? { screens.first }
    var pointerScreen: ScreenDescriptor? { screens.first }
}

@MainActor
private final class PhaseSevenActivationPolicyAdapter: ApplicationActivationPolicyApplying {
    var shouldSucceed = true
    private(set) var requestedVisibility: [Bool] = []

    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        requestedVisibility.append(isVisible)
        return shouldSucceed
    }
}

private final class PhaseSevenPresentationSettingsRepository: PresentationSettingsRepository {
    var storedSettings: PresentationSettings?

    func fetchSettings() -> PresentationSettings? { storedSettings }
    func save(_ settings: PresentationSettings) { storedSettings = settings }
}

@MainActor
private final class RecordingReminderSoundPlayer: ReminderSoundPlaying {
    private(set) var playedSounds: [ReminderSound] = []
    private(set) var stopCount = 0

    func play(_ sound: ReminderSound) {
        playedSounds.append(sound)
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class RecordingReminderNotificationFallback: ReminderNotificationFallbackProviding {
    private(set) var soundEnabledValues: [Bool] = []
    let statusMessage = "Recording fallback"

    func setSoundEnabled(_ isEnabled: Bool) {
        soundEnabledValues.append(isEnabled)
    }

    func requestAuthorization() async -> Bool { true }
    func deliver(_ reminder: Reminder) async -> Bool { true }
}

private func phaseSevenReminder(id: String, title: String = "Phase 7 reminder") -> Reminder {
    let date = Date(timeIntervalSince1970: 100_000)
    return Reminder(
        occurrenceID: ReminderOccurrenceID(
            sourceKind: .calendar,
            sourceIdentifier: id,
            occurrenceDate: date,
            revision: nil
        ),
        title: title,
        detail: "Directly visible on screen",
        triggerDate: date,
        expirationDate: nil,
        presentationMode: .overlay,
        eventContext: ReminderEventContext(
            startDate: date.addingTimeInterval(600),
            calendarTitle: "Work",
            location: nil,
            calendarColorHex: "#3F7DE0"
        )
    )
}

@MainActor
private func phaseSevenStripController(
    screen: ScreenDescriptor
) -> ReminderOverlayWindowController {
    ReminderOverlayWindowController(
        store: ReminderOverlayStore(),
        screenProvider: PhaseSevenScreenProvider(screen: screen),
        presentationAvailability: { _ in true },
        reduceMotion: { true },
        sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) },
        alphaAnimator: { window, endAlpha, _ in
            window.alphaValue = endAlpha
        }
    )
}
