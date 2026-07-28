import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let bundleIdentifier = "com.local.Nudge"
    private static let logger = Logger(subsystem: "com.local.Nudge", category: "Persistence")

    let windowPresentationCoordinator: WindowPresentationCoordinator
    let calendarScheduleCoordinator: CalendarScheduleCoordinator
    let googleTasksSyncCoordinator: GoogleTasksSyncCoordinator
    let googleTasksActionCoordinator: GoogleTasksActionCoordinator
    let googleOAuthClientConfigurationManager: GoogleOAuthClientConfigurationManager
    let launchAtLoginManager: LaunchAtLoginManager
    let persistenceStatusMessage: String?
    private let applicationInstanceLock: ApplicationInstanceLock?
    private let isHostedTestProcess: Bool
    private let lifecycleCoordinator: ApplicationLifecycleCoordinator

    override init() {
        let isHostedTestProcess =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isHostedTestProcess = isHostedTestProcess
        applicationInstanceLock = isHostedTestProcess
            ? nil
            : ApplicationInstanceLock(identifier: Self.bundleIdentifier)
        let openResult = LocalRepositoryContainer.openRecovering()
        let repositoryContainer = openResult.container
        persistenceStatusMessage = openResult.recoveryStatus.message
        if persistenceStatusMessage != nil {
            Self.logger.error("Persistent local cache required recovery")
        }
        let notificationFallback = ReminderNotificationFallback()
        let windowPresentationCoordinator = WindowPresentationCoordinator(
            repositoryContainer: repositoryContainer,
            notificationFallback: notificationFallback
        )
        self.windowPresentationCoordinator = windowPresentationCoordinator
        let httpTransport = URLSessionHTTPTransport()
        let clientSecretStore = KeychainGoogleOAuthClientSecretStore()
        let googleOAuthClientConfigurationManager = GoogleOAuthClientConfigurationManager(
            store: KeychainGoogleOAuthClientConfigurationStore()
        )
        self.googleOAuthClientConfigurationManager = googleOAuthClientConfigurationManager
        let sourceOpener = SystemBrowserOpener()
        let oauthService = GoogleOAuthService(
            configurationProvider: {
                try googleOAuthClientConfigurationManager.configuration()
            },
            clientSecretStore: clientSecretStore,
            credentialStore: KeychainGoogleCredentialStore(),
            oauthClient: GoogleOAuthClient(transport: httpTransport),
            browserOpener: sourceOpener,
            callbackSessionFactory: {
                LoopbackOAuthCallbackSession()
            }
        )
        let googleTasksClient = GoogleTasksClient(transport: httpTransport)
        calendarScheduleCoordinator = GoogleCalendarSyncCoordinator(
            authentication: oauthService,
            provider: GoogleCalendarClient(transport: httpTransport),
            cacheRepository: repositoryContainer.calendarCacheRepository,
            settingsRepository: UserDefaultsCalendarSettingsRepository(),
            reminderConsumer: windowPresentationCoordinator,
            periodicScheduler: GoogleCalendarPeriodicRefreshTimer(),
            notificationFallback: notificationFallback
        )
        let googleTasksSyncCoordinator = GoogleTasksSyncCoordinator(
            authentication: oauthService,
            provider: googleTasksClient,
            taskRepository: repositoryContainer.taskRepository,
            metadataRepository: repositoryContainer.syncMetadataRepository,
            periodicScheduler: GoogleTasksPeriodicRefreshTimer(),
            cacheDidChange: { [weak windowPresentationCoordinator] in
                windowPresentationCoordinator?.reloadTaskPanelCache()
            }
        )
        self.googleTasksSyncCoordinator = googleTasksSyncCoordinator
        googleTasksActionCoordinator = GoogleTasksActionCoordinator(
            authentication: oauthService,
            provider: googleTasksClient,
            taskRepository: repositoryContainer.taskRepository,
            actionRepository: repositoryContainer.taskPendingActionRepository,
            sourceOpener: sourceOpener,
            requestPostActionRefresh: { [weak googleTasksSyncCoordinator] in
                googleTasksSyncCoordinator?.requestRefreshAfterTaskMutation()
            },
            cacheDidChange: { [weak windowPresentationCoordinator] in
                windowPresentationCoordinator?.reloadTaskPanelCache()
            }
        )
        windowPresentationCoordinator.configureTaskActions(googleTasksActionCoordinator)
        googleTasksActionCoordinator.recoverPendingActions()
        launchAtLoginManager = LaunchAtLoginManager()
        lifecycleCoordinator = ApplicationLifecycleCoordinator(
            windowCoordinator: windowPresentationCoordinator,
            calendarCoordinator: calendarScheduleCoordinator,
            tasksCoordinator: googleTasksSyncCoordinator
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard continueAsPrimaryApplicationInstance() else { return }
        windowPresentationCoordinator.applyApplicationActivationPolicy()
        windowPresentationCoordinator.restoreAtLaunch()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-test-surfaces") {
            windowPresentationCoordinator.showTaskPanel()
            windowPresentationCoordinator.showTestReminder()
        }
#endif
        googleTasksSyncCoordinator.restoreAtLaunch()
        lifecycleCoordinator.start()
        Task { @MainActor [calendarScheduleCoordinator] in
            await calendarScheduleCoordinator.restoreAtLaunch()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        calendarScheduleCoordinator.stop()
        googleTasksSyncCoordinator.stop()
        lifecycleCoordinator.stop()
    }

    private func continueAsPrimaryApplicationInstance() -> Bool {
        guard !isHostedTestProcess else { return true }
        guard applicationInstanceLock == nil else { return true }
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        )
        let runningProcessIdentifiers = runningApplications.map(\.processIdentifier)
        let primaryProcessIdentifier = SingleApplicationInstancePolicy.primaryProcessIdentifier(
            currentProcessIdentifier: currentProcessIdentifier,
            runningProcessIdentifiers: runningProcessIdentifiers.filter {
                $0 != currentProcessIdentifier
            }
        )
        runningApplications
            .first { $0.processIdentifier == primaryProcessIdentifier }?
            .activate(options: [.activateAllWindows])
        NSApplication.shared.terminate(nil)
        return false
    }
}
