import Foundation
import Observation

@MainActor
@Observable
final class WindowPresentationCoordinator {
    private let reminderPresentationCoordinator: ReminderPresentationCoordinator
    private let reminderOverlayController: ReminderOverlayWindowController
    private let taskPanelController: TaskPanelWindowController
    private let presentationSettingsRepository: any PresentationSettingsRepository
    private let screenProvider: any ScreenProviding
    private let activationPolicyAdapter: any ApplicationActivationPolicyApplying
    private var presentationSettings: PresentationSettings
    private var testReminderSampleIndex = 0

    init(
        repositoryContainer: LocalRepositoryContainer,
        screenProvider: any ScreenProviding = SystemScreenProvider(),
        presentationSettingsRepository: any PresentationSettingsRepository =
            UserDefaultsPresentationSettingsRepository(),
        activationPolicyAdapter: any ApplicationActivationPolicyApplying =
            SystemApplicationActivationPolicyAdapter(),
        notificationFallback: any ReminderNotificationFallbackProviding = ReminderNotificationFallback(),
        soundPlayer: any ReminderSoundPlaying = SystemReminderSoundPlayer()
    ) {
        self.presentationSettingsRepository = presentationSettingsRepository
        self.screenProvider = screenProvider
        self.activationPolicyAdapter = activationPolicyAdapter
        presentationSettings = presentationSettingsRepository.fetchSettings() ?? .defaultValue
        let reminderStore = ReminderOverlayStore()
        let reminderOverlayController = ReminderOverlayWindowController(
            store: reminderStore,
            screenProvider: screenProvider
        )
        let reminderScheduler = ReminderScheduler(
            repository: repositoryContainer.reminderDeliveryRepository
        )
        let taskPanelStore = TaskPanelStore(
            taskRepository: repositoryContainer.taskRepository,
            stateRepository: repositoryContainer.taskPanelStateRepository,
            syncMetadataRepository: repositoryContainer.syncMetadataRepository
        )

        self.reminderOverlayController = reminderOverlayController
        reminderPresentationCoordinator = ReminderPresentationCoordinator(
            scheduler: reminderScheduler,
            windowController: reminderOverlayController,
            notificationFallback: notificationFallback,
            soundPlayer: soundPlayer
        )
        taskPanelController = TaskPanelWindowController(
            store: taskPanelStore,
            screenProvider: screenProvider
        )
        reminderOverlayController.displayTarget = presentationSettings.reminderDisplayTarget
        reminderOverlayController.presentationDuration = presentationSettings.reminderDuration
        reminderOverlayController.persistsUntilAction =
            presentationSettings.remindersPersistUntilAction
        reminderPresentationCoordinator.reminderSound = presentationSettings.reminderSound
        notificationFallback.setSoundEnabled(presentationSettings.reminderSound.isEnabled)
        reminderOverlayController.presentsOverFullScreenApplications =
            presentationSettings.reminderOverFullScreen
        reminderOverlayController.joinsAllSpaces = presentationSettings.remindersJoinAllSpaces
        taskPanelController.presentsOverFullScreenApplications =
            presentationSettings.taskPanelOverFullScreen
        taskPanelController.joinsAllSpaces = presentationSettings.taskPanelJoinsAllSpaces
    }

    var isReminderOverlayVisible: Bool {
        reminderOverlayController.isVisible
    }

    var isTaskPanelVisible: Bool {
        taskPanelController.isVisible
    }

    var reminderOverFullScreen: Bool {
        presentationSettings.reminderOverFullScreen
    }

    var taskPanelOverFullScreen: Bool {
        presentationSettings.taskPanelOverFullScreen
    }

    var remindersJoinAllSpaces: Bool {
        presentationSettings.remindersJoinAllSpaces
    }

    var taskPanelJoinsAllSpaces: Bool {
        presentationSettings.taskPanelJoinsAllSpaces
    }

    var showsDockIcon: Bool {
        presentationSettings.showsDockIcon
    }

    var availableScreens: [ScreenDescriptor] {
        screenProvider.screens
    }

    var reminderDisplayTarget: PresentationSettings.ReminderDisplayTarget {
        presentationSettings.reminderDisplayTarget
    }

    var reminderDuration: ReminderPresentationDuration {
        presentationSettings.reminderDuration
    }

    var remindersPersistUntilAction: Bool {
        presentationSettings.remindersPersistUntilAction
    }

    var reminderSound: ReminderSound {
        presentationSettings.reminderSound
    }

    var taskPanelScreenIdentifier: String? {
        taskPanelController.screenIdentifier
    }

    var taskPanelCorner: ScreenCorner {
        taskPanelController.corner
    }

    var taskPanelDisplayMode: TaskPanelState.DisplayMode {
        taskPanelController.displayMode
    }

    var taskPanelPlacementMode: TaskPanelState.PlacementMode {
        taskPanelController.placementMode
    }

    var taskPanelOpacity: Double {
        taskPanelController.opacity
    }

    var taskPanelPriorityPalette: TaskPriorityPalette {
        taskPanelController.priorityPalette
    }

    /// Representative samples for source actions, long content, missing metadata, and all-day
    /// presentation.
    private static let testReminderSamples: [(
        title: String,
        context: ReminderEventContext,
        sourceURL: URL?
    )] = [
        (
            "Design review",
            ReminderEventContext(
                startDate: Date(),
                calendarTitle: "Work",
                location: "Room 4",
                calendarColorHex: "#3F7DE0",
                isAllDay: false
            ),
            URL(string: "https://calendar.google.com/calendar/event?eid=nudge-test")
        ),
        (
            "Quarterly platform architecture and reliability planning workshop",
            ReminderEventContext(
                startDate: Date(),
                calendarTitle: "Engineering Leadership Calendar",
                location: "Amsterdam HQ · Building B · Meeting room Willem-Alexander",
                calendarColorHex: "#B05A2C",
                isAllDay: false
            ),
            nil
        ),
        (
            "Dentist",
            ReminderEventContext(startDate: Date(), calendarTitle: nil, location: nil),
            nil
        ),
        (
            "Company holiday",
            ReminderEventContext(
                startDate: Date(),
                calendarTitle: "Company Calendar",
                location: nil,
                calendarColorHex: "#2E8B74",
                isAllDay: true
            ),
            nil
        ),
    ]

    func showTestReminder() {
        let now = Date()
        let sample = Self.testReminderSamples[
            testReminderSampleIndex % Self.testReminderSamples.count
        ]
        testReminderSampleIndex += 1
        let startDate = sample.context.isAllDay == true
            ? Calendar.current.startOfDay(for: now)
            : now.addingTimeInterval(10 * 60)
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: UUID().uuidString,
                occurrenceDate: now,
                revision: nil
            ),
            title: sample.title,
            detail: nil,
            triggerDate: now,
            expirationDate: now.addingTimeInterval(15 * 60),
            presentationMode: .overlay,
            sourceURL: sample.sourceURL,
            eventContext: ReminderEventContext(
                startDate: startDate,
                calendarTitle: sample.context.calendarTitle,
                location: sample.context.location,
                calendarColorHex: sample.context.calendarColorHex,
                isAllDay: sample.context.isAllDay
            )
        )
        try? reminderPresentationCoordinator.process([reminder])
    }

    func dismissTestReminder() {
        reminderPresentationCoordinator.dismissCurrentReminder()
    }

    func showTaskPanel() {
        taskPanelController.show()
    }

    func hideTaskPanel() {
        taskPanelController.hide()
    }

    func setTaskPanelCorner(_ corner: ScreenCorner) {
        taskPanelController.corner = corner
    }

    func resetTaskPanelPosition() {
        taskPanelController.resetPosition()
    }

    func setReminderDisplayTarget(_ target: PresentationSettings.ReminderDisplayTarget) {
        presentationSettings.reminderDisplayTarget = target
        presentationSettingsRepository.save(presentationSettings)
        reminderOverlayController.displayTarget = target
        reminderOverlayController.reposition()
    }

    func setReminderDuration(seconds: Int) {
        let duration = ReminderPresentationDuration(seconds: seconds)
        presentationSettings.reminderDuration = duration
        presentationSettingsRepository.save(presentationSettings)
        reminderOverlayController.presentationDuration = duration
    }

    func setRemindersPersistUntilAction(_ shouldPersist: Bool) {
        presentationSettings.remindersPersistUntilAction = shouldPersist
        presentationSettingsRepository.save(presentationSettings)
        reminderOverlayController.persistsUntilAction = shouldPersist
    }

    func setReminderSound(_ sound: ReminderSound) {
        presentationSettings.reminderSound = sound
        presentationSettingsRepository.save(presentationSettings)
        reminderPresentationCoordinator.reminderSound = sound
        reminderPresentationCoordinator.setNotificationFallbackSoundEnabled(sound.isEnabled)
        if sound.isEnabled {
            reminderPresentationCoordinator.previewReminderSound()
        } else {
            reminderPresentationCoordinator.stopReminderSound()
        }
    }

    func setTaskPanelScreenIdentifier(_ identifier: String?) {
        taskPanelController.setScreenIdentifier(identifier)
    }

    func setTaskPanelDisplayMode(_ mode: TaskPanelState.DisplayMode) {
        taskPanelController.setDisplayMode(mode)
    }

    func setTaskPanelPlacementMode(_ mode: TaskPanelState.PlacementMode) {
        taskPanelController.setPlacementMode(mode)
    }

    func setTaskPanelOpacity(_ opacity: Double) {
        taskPanelController.setOpacity(opacity)
    }

    func setTaskPanelPriorityColor(_ colorHex: String, for priority: TaskPriority) {
        taskPanelController.setPriorityColor(colorHex, for: priority)
    }

    func setReminderOverFullScreen(_ isAllowed: Bool) {
        presentationSettings.reminderOverFullScreen = isAllowed
        presentationSettingsRepository.save(presentationSettings)
        reminderOverlayController.presentsOverFullScreenApplications = isAllowed
    }

    func setTaskPanelOverFullScreen(_ isAllowed: Bool) {
        presentationSettings.taskPanelOverFullScreen = isAllowed
        presentationSettingsRepository.save(presentationSettings)
        taskPanelController.presentsOverFullScreenApplications = isAllowed
    }

    func setRemindersJoinAllSpaces(_ shouldJoin: Bool) {
        presentationSettings.remindersJoinAllSpaces = shouldJoin
        presentationSettingsRepository.save(presentationSettings)
        reminderOverlayController.joinsAllSpaces = shouldJoin
    }

    func setTaskPanelJoinsAllSpaces(_ shouldJoin: Bool) {
        presentationSettings.taskPanelJoinsAllSpaces = shouldJoin
        presentationSettingsRepository.save(presentationSettings)
        taskPanelController.joinsAllSpaces = shouldJoin
    }

    @discardableResult
    func setShowsDockIcon(_ shouldShow: Bool) -> Bool {
        guard activationPolicyAdapter.setDockIconVisible(shouldShow) else {
            return false
        }
        presentationSettings.showsDockIcon = shouldShow
        presentationSettingsRepository.save(presentationSettings)
        return true
    }

    func applyApplicationActivationPolicy() {
        _ = activationPolicyAdapter.setDockIconVisible(presentationSettings.showsDockIcon)
    }

    func restoreAtLaunch() {
        taskPanelController.restoreIfEnabled()
    }

    func reloadTaskPanelCache() {
        taskPanelController.reloadCache()
    }

    func prepareForSleep() {
        reminderPresentationCoordinator.prepareForSleep()
        taskPanelController.prepareForSleep()
    }

    func setSessionActive(_ isActive: Bool) {
        reminderPresentationCoordinator.setSessionActive(
            isActive,
            recoverIfActivated: false
        )
    }

    func recoverAfterLifecycleChange() {
        reminderPresentationCoordinator.recoverAfterLifecycleChange()
        taskPanelController.recoverAfterLifecycleChange()
        reminderOverlayController.reposition()
    }

    func configureTaskActions(_ actionCoordinator: GoogleTasksActionCoordinator) {
        taskPanelController.configureActions(actionCoordinator)
    }

    func replaceCalendarReminders(with reminders: [Reminder]) throws {
        try reminderPresentationCoordinator.replaceCalendarReminders(with: reminders)
    }
}

extension WindowPresentationCoordinator: CalendarReminderConsumer {}
