#if DEBUG
import Foundation

@MainActor
struct ScreenshotDemoDependencies {
    enum BlockedOperationError: Error {
        case unavailableInScreenshotDemo
    }

    final class BlockedHTTPTransport: HTTPTransport {
        private(set) var requestCount = 0

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requestCount += 1
            throw BlockedOperationError.unavailableInScreenshotDemo
        }
    }

    final class InMemoryCredentialStore: GoogleCredentialStore {
        private(set) var loadCount = 0
        private var credential: GoogleOAuthCredential?

        func loadCredential() throws -> GoogleOAuthCredential? {
            loadCount += 1
            return credential
        }

        func saveCredential(_ credential: GoogleOAuthCredential) throws {
            self.credential = credential
        }

        func deleteCredential() throws {
            credential = nil
        }
    }

    final class InMemoryClientSecretStore: GoogleOAuthClientSecretStore {
        private var clientSecret: String?

        func loadClientSecret() throws -> String? {
            clientSecret
        }

        func saveClientSecret(_ clientSecret: String) throws {
            self.clientSecret = clientSecret
        }

        func deleteClientSecret() throws {
            clientSecret = nil
        }
    }

    final class InMemoryClientConfigurationStore: GoogleOAuthClientConfigurationStore {
        private var configuration: GoogleOAuthClientConfiguration?

        func loadConfiguration() throws -> GoogleOAuthClientConfiguration? {
            configuration
        }

        func saveConfiguration(_ configuration: GoogleOAuthClientConfiguration) throws {
            self.configuration = configuration
        }

        func deleteConfiguration() throws {
            configuration = nil
        }
    }

    final class BlockedBrowserOpener: SystemBrowserOpening {
        private(set) var openCount = 0

        func open(_ url: URL) -> Bool {
            openCount += 1
            return false
        }
    }

    final class BlockedCallbackSession: OAuthCallbackSession {
        func start() async throws -> URL {
            throw BlockedOperationError.unavailableInScreenshotDemo
        }

        func waitForCallback() async throws -> URL {
            throw BlockedOperationError.unavailableInScreenshotDemo
        }

        func stop() {}
    }

    final class NoopCalendarScheduler: GoogleCalendarPeriodicRefreshScheduling {
        private(set) var startCount = 0

        func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
            startCount += 1
        }

        func stop() {}
    }

    final class NoopTasksScheduler: GoogleTasksPeriodicRefreshScheduling {
        private(set) var startCount = 0

        func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
            startCount += 1
        }

        func stop() {}
    }

    final class InMemoryPresentationSettingsRepository: PresentationSettingsRepository {
        private var settings: PresentationSettings?

        init(settings: PresentationSettings) {
            self.settings = settings
        }

        func fetchSettings() -> PresentationSettings? {
            settings
        }

        func save(_ settings: PresentationSettings) {
            self.settings = settings
        }
    }

    final class InMemoryCalendarSettingsRepository: CalendarSettingsRepository {
        private var settings: CalendarSettings?

        init(settings: CalendarSettings) {
            self.settings = settings
        }

        func fetchSettings() -> CalendarSettings? {
            settings
        }

        func save(_ settings: CalendarSettings) {
            self.settings = settings
        }
    }

    final class InMemoryTasksSettingsRepository: GoogleTasksSettingsRepository {
        private var settings: GoogleTasksSettings?

        init(settings: GoogleTasksSettings) {
            self.settings = settings
        }

        func fetchSettings() -> GoogleTasksSettings? {
            settings
        }

        func save(_ settings: GoogleTasksSettings) {
            self.settings = settings
        }
    }

    final class NoopLaunchAtLoginService: LaunchAtLoginService {
        var status: LaunchAtLoginServiceStatus { .notRegistered }
        private(set) var mutationCount = 0

        func register() throws {
            mutationCount += 1
        }

        func unregister() throws {
            mutationCount += 1
        }

        func openSystemSettings() {
            mutationCount += 1
        }
    }

    final class NoopNotificationFallback: ReminderNotificationFallbackProviding {
        private(set) var statusMessage = "Notification fallback is off."

        func setSoundEnabled(_ isEnabled: Bool) {}

        func requestAuthorization() async -> Bool {
            false
        }

        func deliver(_ reminder: Reminder) async -> Bool {
            false
        }
    }

    final class NoopSoundPlayer: ReminderSoundPlaying {
        func play(_ sound: ReminderSound) {}
        func stop() {}
    }

    final class NoopActivationPolicyAdapter: ApplicationActivationPolicyApplying {
        func setDockIconVisible(_ isVisible: Bool) -> Bool {
            true
        }
    }

    final class FixedScreenProvider: ScreenProviding {
        private let screen = ScreenDescriptor(
            id: "demo-main-display",
            name: "Main Display",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 28, width: 1440, height: 872),
            isMain: true
        )

        var screens: [ScreenDescriptor] { [screen] }
        var mainScreen: ScreenDescriptor? { screen }
        var pointerScreen: ScreenDescriptor? { screen }
    }

    static let referenceDate = Date(timeIntervalSince1970: 1_785_236_400)

    let repositoryContainer: LocalRepositoryContainer
    let notificationFallback = NoopNotificationFallback()
    let screenProvider = FixedScreenProvider()
    let presentationSettingsRepository: InMemoryPresentationSettingsRepository
    let activationPolicyAdapter = NoopActivationPolicyAdapter()
    let soundPlayer = NoopSoundPlayer()
    let transport = BlockedHTTPTransport()
    let clientSecretStore = InMemoryClientSecretStore()
    let credentialStore = InMemoryCredentialStore()
    let clientConfigurationStore = InMemoryClientConfigurationStore()
    let browserOpener = BlockedBrowserOpener()
    let calendarScheduler = NoopCalendarScheduler()
    let tasksScheduler = NoopTasksScheduler()
    let calendarSettingsRepository: InMemoryCalendarSettingsRepository
    let tasksSettingsRepository: InMemoryTasksSettingsRepository
    let launchAtLoginService = NoopLaunchAtLoginService()

    init() throws {
        repositoryContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        presentationSettingsRepository = InMemoryPresentationSettingsRepository(
            settings: PresentationSettings(
                schemaVersion: PresentationSettings.currentSchemaVersion,
                reminderDisplayTarget: .pointer,
                reminderDuration: .defaultValue,
                remindersPersistUntilAction: false,
                reminderSound: .off,
                reminderOverFullScreen: false,
                taskPanelOverFullScreen: false,
                remindersJoinAllSpaces: true,
                taskPanelJoinsAllSpaces: true,
                showsDockIcon: false
            )
        )
        calendarSettingsRepository = InMemoryCalendarSettingsRepository(
            settings: CalendarSettings(
                schemaVersion: 3,
                selectedCalendarIdentifiers: Set(Self.calendarFixtures.map(\.id)),
                hasConfiguredSelection: true,
                lookAheadDays: 14,
                usesNotificationFallback: false
            )
        )
        tasksSettingsRepository = InMemoryTasksSettingsRepository(
            settings: .defaultValue
        )
        try seedRepositories()
    }

    func restoreCurrentTaskMetadata() throws {
        try repositoryContainer.syncMetadataRepository.save(Self.currentMetadata())
    }

    static let calendarFixtures = [
        CalendarDescriptor(
            id: "demo-work",
            title: "Work",
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: true,
            defaultReminders: [.init(method: "popup", minutes: 10)],
            backgroundColorHex: "#3F7DE0"
        ),
        CalendarDescriptor(
            id: "demo-personal",
            title: "Personal",
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: false,
            defaultReminders: [.init(method: "popup", minutes: 15)],
            backgroundColorHex: "#2E8B74"
        ),
        CalendarDescriptor(
            id: "demo-birthdays",
            title: "Birthdays",
            timeZoneIdentifier: "UTC",
            isSelectedInGoogleCalendar: true,
            isPrimary: false,
            defaultReminders: [],
            backgroundColorHex: "#B05A2C"
        ),
    ]

    static let taskListFixtures = [
        TaskList(id: "demo-today", title: "Today"),
        TaskList(id: "demo-projects", title: "Personal Projects"),
    ]

    static let taskFixtures = [
        TaskItem(
            id: "demo-task-1",
            taskListID: "demo-today",
            title: "Review the project brief",
            notes: nil,
            completionState: .incomplete,
            dueDate: .init(year: 2026, month: 7, day: 27),
            localTimeOverride: .init(hour: 9, minute: 30, timeZoneIdentifier: "UTC"),
            priority: .high
        ),
        TaskItem(
            id: "demo-task-2",
            taskListID: "demo-today",
            title: "Prepare slides for Friday",
            notes: nil,
            completionState: .incomplete,
            dueDate: .init(year: 2026, month: 7, day: 27),
            localTimeOverride: .init(hour: 11, minute: 0, timeZoneIdentifier: "UTC"),
            priority: .high
        ),
        TaskItem(
            id: "demo-task-3",
            taskListID: "demo-today",
            title: "Book a dentist appointment",
            notes: nil,
            completionState: .incomplete,
            dueDate: .init(year: 2026, month: 7, day: 28),
            localTimeOverride: nil,
            priority: .medium
        ),
        TaskItem(
            id: "demo-task-4",
            taskListID: "demo-today",
            title: "Pick up groceries for dinner",
            notes: nil,
            completionState: .incomplete,
            dueDate: .init(year: 2026, month: 7, day: 27),
            localTimeOverride: nil,
            priority: .low
        ),
        TaskItem(
            id: "demo-task-5",
            taskListID: "demo-today",
            title: "Plan the weekend hike",
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil,
            priority: .none
        ),
    ]

    static func reminderFixture() -> Reminder {
        Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: "demo-design-review",
                occurrenceDate: referenceDate,
                revision: nil
            ),
            title: "Design review",
            detail: nil,
            triggerDate: referenceDate,
            expirationDate: referenceDate.addingTimeInterval(15 * 60),
            presentationMode: .overlay,
            sourceURL: URL(string: "https://calendar.google.com/calendar/event?eid=demo"),
            eventContext: ReminderEventContext(
                startDate: referenceDate.addingTimeInterval(10 * 60),
                calendarTitle: "Work",
                location: "Room 4",
                calendarColorHex: "#3F7DE0",
                isAllDay: false
            )
        )
    }

    /// An overdue Google Task nag that also covers a second open task.
    static func taskNagFixture() -> Reminder {
        Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .task,
                sourceIdentifier: "task-nag:demo-task-1",
                occurrenceDate: referenceDate,
                revision: nil
            ),
            title: "Review the project brief",
            detail: nil,
            triggerDate: referenceDate,
            expirationDate: nil,
            presentationMode: .overlay,
            sourceURL: URL(string: "https://tasks.google.com/task/demo"),
            taskContext: ReminderTaskContext(
                taskIDs: ["demo-task-1", "demo-task-2"],
                primaryTaskListID: "demo-today",
                urgency: .overdue,
                dueDate: .init(year: 2026, month: 7, day: 25),
                daysOverdue: 3,
                daysOpen: 6
            ),
            actions: [.completeTask, .notToday]
        )
    }

    /// The fixed line the bird says while perched on the calendar alert.
    static let builtInClientID = "screenshot-demo.apps.googleusercontent.com"
    static let builtInClientSecret = "screenshot-demo-secret"
    static let birdAlertLine = "Design review in a few. Find your headphones now, not in a panic later."

    private func seedRepositories() throws {
        try repositoryContainer.calendarCacheRepository.replaceCalendars(Self.calendarFixtures)
        try repositoryContainer.calendarCacheRepository.replaceEvents([])
        try repositoryContainer.calendarCacheRepository.saveMetadata(Self.currentMetadata())
        try repositoryContainer.taskRepository.replaceCache(
            taskLists: Self.taskListFixtures,
            tasks: Self.taskFixtures
        )
        try repositoryContainer.taskPanelStateRepository.save(
            TaskPanelState(
                isEnabled: true,
                displayMode: .expanded,
                corner: .topTrailing,
                selectedTaskListID: "demo-today",
                opacity: 1,
                placementMode: .anchored,
                expandedHeight: 420
            )
        )
        try repositoryContainer.syncMetadataRepository.save(Self.currentMetadata())
    }

    private static func currentMetadata() -> SyncMetadata {
        return SyncMetadata(
            status: .current,
            lastAttemptAt: referenceDate,
            lastSuccessfulRefreshAt: referenceDate,
            statusMessage: "Demo data is ready."
        )
    }
}
#endif
