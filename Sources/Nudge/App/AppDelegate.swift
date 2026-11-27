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
    let taskNagCoordinator: TaskNagCoordinator
    let persistenceStatusMessage: String?
    private let reminderActionRouter: ReminderActionRouter
    private let applicationInstanceLock: ApplicationInstanceLock?
    private let isHostedTestProcess: Bool
    private let lifecycleCoordinator: ApplicationLifecycleCoordinator
#if DEBUG
    private let screenshotDemoConfiguration: ScreenshotDemoConfiguration?
    private let screenshotDemoWasRequested: Bool
    private let screenshotDemoDependencies: ScreenshotDemoDependencies?
    private var screenshotDemoCaptureController: ScreenshotDemoCaptureController?
#endif

    override init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isHostedTestProcess =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isHostedTestProcess = isHostedTestProcess
#if DEBUG
        let screenshotDemoWasRequested = ScreenshotDemoConfiguration.isRequested(
            arguments: arguments
        )
        self.screenshotDemoWasRequested = screenshotDemoWasRequested
        screenshotDemoConfiguration = screenshotDemoWasRequested
            ? try? ScreenshotDemoConfiguration.parse(arguments: arguments)
            : nil
        let screenshotDemoDependencies = screenshotDemoWasRequested
            ? try! ScreenshotDemoDependencies()
            : nil
        self.screenshotDemoDependencies = screenshotDemoDependencies
#endif

        let repositoryContainer: LocalRepositoryContainer
        let notificationFallback: any ReminderNotificationFallbackProviding
        let screenProvider: any ScreenProviding
        let presentationSettingsRepository: any PresentationSettingsRepository
        let activationPolicyAdapter: any ApplicationActivationPolicyApplying
        let soundPlayer: any ReminderSoundPlaying
        let httpTransport: any HTTPTransport
        let clientSecretStore: any GoogleOAuthClientSecretStore
        let credentialStore: any GoogleCredentialStore
        let sourceOpener: any SystemBrowserOpening
        let calendarScheduler: any GoogleCalendarPeriodicRefreshScheduling
        let tasksScheduler: any GoogleTasksPeriodicRefreshScheduling
        let calendarSettingsRepository: any CalendarSettingsRepository
        let tasksSettingsRepository: any GoogleTasksSettingsRepository
        let oauthConfigurationManager: GoogleOAuthClientConfigurationManager

#if DEBUG
        if let screenshotDemoDependencies {
            applicationInstanceLock = nil
            repositoryContainer = screenshotDemoDependencies.repositoryContainer
            persistenceStatusMessage = nil
            notificationFallback = screenshotDemoDependencies.notificationFallback
            screenProvider = screenshotDemoDependencies.screenProvider
            presentationSettingsRepository =
                screenshotDemoDependencies.presentationSettingsRepository
            activationPolicyAdapter = screenshotDemoDependencies.activationPolicyAdapter
            soundPlayer = screenshotDemoDependencies.soundPlayer
            httpTransport = screenshotDemoDependencies.transport
            clientSecretStore = screenshotDemoDependencies.clientSecretStore
            credentialStore = screenshotDemoDependencies.credentialStore
            sourceOpener = screenshotDemoDependencies.browserOpener
            calendarScheduler = screenshotDemoDependencies.calendarScheduler
            tasksScheduler = screenshotDemoDependencies.tasksScheduler
            calendarSettingsRepository = screenshotDemoDependencies.calendarSettingsRepository
            tasksSettingsRepository = screenshotDemoDependencies.tasksSettingsRepository
            oauthConfigurationManager = GoogleOAuthClientConfigurationManager(
                store: screenshotDemoDependencies.clientConfigurationStore,
                environment: [:],
                bundledClientID: nil,
                bundledClientSecret: nil
            )
            launchAtLoginManager = LaunchAtLoginManager(
                service: screenshotDemoDependencies.launchAtLoginService
            )
        } else {
            applicationInstanceLock = isHostedTestProcess
                ? nil
                : ApplicationInstanceLock(identifier: Self.bundleIdentifier)
            let openResult = LocalRepositoryContainer.openRecovering()
            repositoryContainer = openResult.container
            persistenceStatusMessage = openResult.recoveryStatus.message
            if persistenceStatusMessage != nil {
                Self.logger.error("Persistent local cache required recovery")
            }
            notificationFallback = ReminderNotificationFallback()
            screenProvider = SystemScreenProvider()
            presentationSettingsRepository = UserDefaultsPresentationSettingsRepository()
            activationPolicyAdapter = SystemApplicationActivationPolicyAdapter()
            soundPlayer = SystemReminderSoundPlayer()
            httpTransport = URLSessionHTTPTransport()
            clientSecretStore = KeychainGoogleOAuthClientSecretStore()
            credentialStore = KeychainGoogleCredentialStore()
            sourceOpener = SystemBrowserOpener()
            calendarScheduler = GoogleCalendarPeriodicRefreshTimer()
            tasksScheduler = GoogleTasksPeriodicRefreshTimer()
            calendarSettingsRepository = UserDefaultsCalendarSettingsRepository()
            tasksSettingsRepository = UserDefaultsGoogleTasksSettingsRepository()
            oauthConfigurationManager = GoogleOAuthClientConfigurationManager(
                store: KeychainGoogleOAuthClientConfigurationStore()
            )
            launchAtLoginManager = LaunchAtLoginManager()
        }
#else
        applicationInstanceLock = isHostedTestProcess
            ? nil
            : ApplicationInstanceLock(identifier: Self.bundleIdentifier)
        let openResult = LocalRepositoryContainer.openRecovering()
        repositoryContainer = openResult.container
        persistenceStatusMessage = openResult.recoveryStatus.message
        if persistenceStatusMessage != nil {
            Self.logger.error("Persistent local cache required recovery")
        }
        notificationFallback = ReminderNotificationFallback()
        screenProvider = SystemScreenProvider()
        presentationSettingsRepository = UserDefaultsPresentationSettingsRepository()
        activationPolicyAdapter = SystemApplicationActivationPolicyAdapter()
        soundPlayer = SystemReminderSoundPlayer()
        httpTransport = URLSessionHTTPTransport()
        clientSecretStore = KeychainGoogleOAuthClientSecretStore()
        credentialStore = KeychainGoogleCredentialStore()
        sourceOpener = SystemBrowserOpener()
        calendarScheduler = GoogleCalendarPeriodicRefreshTimer()
        tasksScheduler = GoogleTasksPeriodicRefreshTimer()
        calendarSettingsRepository = UserDefaultsCalendarSettingsRepository()
        tasksSettingsRepository = UserDefaultsGoogleTasksSettingsRepository()
        oauthConfigurationManager = GoogleOAuthClientConfigurationManager(
            store: KeychainGoogleOAuthClientConfigurationStore()
        )
        launchAtLoginManager = LaunchAtLoginManager()
#endif
        googleOAuthClientConfigurationManager = oauthConfigurationManager

        let windowPresentationCoordinator = WindowPresentationCoordinator(
            repositoryContainer: repositoryContainer,
            screenProvider: screenProvider,
            presentationSettingsRepository: presentationSettingsRepository,
            activationPolicyAdapter: activationPolicyAdapter,
            notificationFallback: notificationFallback,
            soundPlayer: soundPlayer
        )
        self.windowPresentationCoordinator = windowPresentationCoordinator
        // Screenshot captures and hosted tests must never read or write the user's real
        // preferences or Application Support files.
#if DEBUG
        let usesIsolatedLocalState = isHostedTestProcess || screenshotDemoWasRequested
#else
        let usesIsolatedLocalState = isHostedTestProcess
#endif
        let taskNagCoordinator = TaskNagCoordinator(
            taskRepository: repositoryContainer.taskRepository,
            historyRepository: usesIsolatedLocalState
                ? InMemoryTaskNagHistoryRepository()
                : FileTaskNagHistoryRepository(),
            settingsRepository: usesIsolatedLocalState
                ? InMemoryTaskNagSettingsRepository()
                : UserDefaultsTaskNagSettingsRepository(),
            reminderSink: { [weak windowPresentationCoordinator] reminders in
                try windowPresentationCoordinator?.replaceTaskReminders(with: reminders)
            }
        )
        self.taskNagCoordinator = taskNagCoordinator
        let oauthService = GoogleOAuthService(
            configurationProvider: {
                try oauthConfigurationManager.configuration()
            },
            clientSecretStore: clientSecretStore,
            credentialStore: credentialStore,
            oauthClient: GoogleOAuthClient(transport: httpTransport),
            browserOpener: sourceOpener,
            callbackSessionFactory: {
#if DEBUG
                if screenshotDemoWasRequested {
                    return ScreenshotDemoDependencies.BlockedCallbackSession()
                }
#endif
                return LoopbackOAuthCallbackSession()
            }
        )
        let googleTasksClient = GoogleTasksClient(transport: httpTransport)
        calendarScheduleCoordinator = GoogleCalendarSyncCoordinator(
            authentication: oauthService,
            provider: GoogleCalendarClient(transport: httpTransport),
            cacheRepository: repositoryContainer.calendarCacheRepository,
            settingsRepository: calendarSettingsRepository,
            reminderConsumer: windowPresentationCoordinator,
            periodicScheduler: calendarScheduler,
            notificationFallback: notificationFallback
        )
        let googleTasksSyncCoordinator = GoogleTasksSyncCoordinator(
            authentication: oauthService,
            provider: googleTasksClient,
            taskRepository: repositoryContainer.taskRepository,
            metadataRepository: repositoryContainer.syncMetadataRepository,
            periodicScheduler: tasksScheduler,
            settingsRepository: tasksSettingsRepository,
            cacheDidChange: { [weak windowPresentationCoordinator, weak taskNagCoordinator] in
                windowPresentationCoordinator?.reloadTaskPanelCache()
                taskNagCoordinator?.recompute()
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
            cacheDidChange: { [weak windowPresentationCoordinator, weak taskNagCoordinator] in
                windowPresentationCoordinator?.reloadTaskPanelCache()
                taskNagCoordinator?.recompute()
            }
        )
        windowPresentationCoordinator.configureTaskActions(googleTasksActionCoordinator)
        let reminderActionRouter = ReminderActionRouter(
            taskRepository: repositoryContainer.taskRepository,
            taskActions: googleTasksActionCoordinator,
            taskNags: taskNagCoordinator
        )
        self.reminderActionRouter = reminderActionRouter
        windowPresentationCoordinator.configureReminderHooks(
            actionHandler: { [weak reminderActionRouter] action, reminder in
                await reminderActionRouter?.perform(action, for: reminder) ?? false
            },
            onPresented: { [weak taskNagCoordinator] reminder in
                if reminder.occurrenceID.sourceKind == .task {
                    taskNagCoordinator?.reminderWasPresented(reminder)
                }
            },
            onSnoozed: { [weak taskNagCoordinator] reminder, date in
                if reminder.occurrenceID.sourceKind == .task {
                    taskNagCoordinator?.reminderWasSnoozed(reminder, until: date)
                }
            }
        )
        windowPresentationCoordinator.onLifecycleRecovery = { [weak taskNagCoordinator] in
            taskNagCoordinator?.recompute()
        }
        googleTasksActionCoordinator.recoverPendingActions()
#if DEBUG
        try? screenshotDemoDependencies?.restoreCurrentTaskMetadata()
#endif
        lifecycleCoordinator = ApplicationLifecycleCoordinator(
            windowCoordinator: windowPresentationCoordinator,
            calendarCoordinator: calendarScheduleCoordinator,
            tasksCoordinator: googleTasksSyncCoordinator
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if screenshotDemoWasRequested {
            guard let screenshotDemoConfiguration,
                  let repositoryContainer = screenshotDemoDependencies?.repositoryContainer else {
                FileHandle.standardError.write(
                    Data("Nudge screenshot capture arguments are invalid.\n".utf8)
                )
                NSApplication.shared.terminate(nil)
                return
            }
            let controller = ScreenshotDemoCaptureController(
                configuration: screenshotDemoConfiguration,
                calendarCoordinator: calendarScheduleCoordinator,
                googleTasksCoordinator: googleTasksSyncCoordinator,
                googleOAuthConfigurationManager: googleOAuthClientConfigurationManager,
                windowCoordinator: windowPresentationCoordinator,
                launchAtLoginManager: launchAtLoginManager,
                repositoryContainer: repositoryContainer
            )
            screenshotDemoCaptureController = controller
            controller.start()
            return
        }
#endif
        guard continueAsPrimaryApplicationInstance() else { return }
        if !isHostedTestProcess {
            LaunchAtLoginDefaultApplier().applyIfNeeded(to: launchAtLoginManager)
        }
        windowPresentationCoordinator.applyApplicationActivationPolicy()
        windowPresentationCoordinator.restoreAtLaunch()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-test-surfaces") {
            windowPresentationCoordinator.showTaskPanel()
            windowPresentationCoordinator.showTestReminder()
        }
#endif
        googleTasksSyncCoordinator.restoreAtLaunch()
        taskNagCoordinator.recompute()
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
