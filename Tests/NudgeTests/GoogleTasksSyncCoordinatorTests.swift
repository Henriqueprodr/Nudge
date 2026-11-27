import Foundation
import XCTest
@testable import Nudge

final class GoogleTasksSyncCoordinatorTests: XCTestCase {
    @MainActor
    func testLaunchAndPeriodicTriggersUseFifteenMinuteDefaultWithoutPerSecondPolling() async {
        let provider = FakeGoogleTasksProvider(outcomes: [
            .success(.empty),
            .success(.empty),
        ])
        let scheduler = FakePeriodicRefreshScheduler()
        let coordinator = makeCoordinator(provider: provider, scheduler: scheduler)

        coordinator.restoreAtLaunch()
        await waitUntil { provider.callCount == 1 && !coordinator.isRefreshing }

        XCTAssertEqual(
            scheduler.interval,
            GoogleTasksSyncCoordinator.defaultPeriodicInterval
        )
        XCTAssertEqual(scheduler.interval, 900)
        scheduler.fire()
        await waitUntil { provider.callCount == 2 && !coordinator.isRefreshing }

        XCTAssertEqual(provider.callCount, 2)
        coordinator.stop()
    }

    @MainActor
    func testManualWakeAndPeriodicTriggersCoalesceIntoOneFollowUpWithoutOverlap() async {
        let provider = FakeGoogleTasksProvider(outcomes: [
            .success(.empty),
            .success(.empty),
        ])
        provider.suspendFirstRequest = true
        let coordinator = makeCoordinator(provider: provider)

        coordinator.requestRefresh(.manual)
        await waitUntil { provider.callCount == 1 }
        coordinator.requestRefresh(.wake)
        coordinator.requestRefresh(.periodic)
        coordinator.requestRefresh(.manual)
        provider.resumeFirstRequest()
        await waitUntil { provider.callCount == 2 && !coordinator.isRefreshing }

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(provider.maximumConcurrentRequestCount, 1)
    }

    @MainActor
    func testPeriodicIntervalRestoresAndReschedulesOnlyTasksTimer() {
        let scheduler = FakePeriodicRefreshScheduler()
        let settings = InMemoryGoogleTasksSettingsRepository(
            settings: GoogleTasksSettings(
                schemaVersion: 1,
                periodicRefreshInterval: PeriodicRefreshInterval(minutes: 60)
            )
        )
        let coordinator = makeCoordinator(
            provider: FakeGoogleTasksProvider(outcomes: []),
            scheduler: scheduler,
            settingsRepository: settings
        )

        coordinator.restoreAtLaunch()
        coordinator.setPeriodicRefreshInterval(PeriodicRefreshInterval(minutes: 5))

        XCTAssertEqual(scheduler.intervals, [3_600, 300])
        XCTAssertEqual(scheduler.stopCount, 1)
        XCTAssertEqual(coordinator.periodicInterval, 300)
        XCTAssertEqual(settings.settings.periodicRefreshInterval.minutes, 5)
        coordinator.stop()
    }

    @MainActor
    func testSuccessfulAuthenticationImmediatelyRefreshesCache() async {
        let authentication = FakeGoogleAuthentication(hasCredential: false)
        let provider = FakeGoogleTasksProvider(outcomes: [
            .success(
                GoogleTasksSnapshot(
                    taskLists: [TaskList(id: "inbox", title: "Inbox")],
                    tasks: [TaskItem.incomplete(id: "after-auth")]
                )
            ),
        ])
        let taskRepository = InMemoryTaskRepository()
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository
        )

        await coordinator.signIn()

        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertEqual(authentication.signInCount, 1)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(taskRepository.tasks.map(\.id), ["after-auth"])
    }

    @MainActor
    func testClientSecretConfigurationPersistsAcrossCoordinatorReconstructionAndCanBeRemoved() {
        let sensitiveMarker = "fake-client-secret-marker"
        let authentication = FakeGoogleAuthentication(
            clientSecret: nil,
            hasCredential: false
        )
        let firstCoordinator = makeCoordinator(
            authentication: authentication,
            provider: FakeGoogleTasksProvider(outcomes: [])
        )

        XCTAssertTrue(firstCoordinator.isClientIDConfigured)
        XCTAssertFalse(firstCoordinator.hasStoredClientSecret)
        XCTAssertFalse(firstCoordinator.isOAuthClientConfigured)
        XCTAssertTrue(firstCoordinator.saveClientSecret(sensitiveMarker))
        XCTAssertTrue(firstCoordinator.hasStoredClientSecret)
        XCTAssertTrue(firstCoordinator.isOAuthClientConfigured)
        XCTAssertFalse(firstCoordinator.authenticationStatusMessage.contains(sensitiveMarker))

        let reconstructedCoordinator = makeCoordinator(
            authentication: authentication,
            provider: FakeGoogleTasksProvider(outcomes: [])
        )
        XCTAssertTrue(reconstructedCoordinator.hasStoredClientSecret)
        XCTAssertTrue(reconstructedCoordinator.isOAuthClientConfigured)

        reconstructedCoordinator.removeClientSecret()
        XCTAssertFalse(reconstructedCoordinator.hasStoredClientSecret)
        XCTAssertFalse(reconstructedCoordinator.isOAuthClientConfigured)
        XCTAssertFalse(reconstructedCoordinator.authenticationStatusMessage.contains(sensitiveMarker))
    }

    @MainActor
    func testMissingClientIDDoesNotTouchKeychainBackedAuthenticationState() {
        let authentication = FakeGoogleAuthentication(
            hasClientID: false,
            clientSecret: "stored-but-unusable-client-secret",
            hasCredential: true
        )

        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: FakeGoogleTasksProvider(outcomes: [])
        )

        XCTAssertFalse(coordinator.isClientIDConfigured)
        XCTAssertFalse(coordinator.hasStoredClientSecret)
        XCTAssertFalse(coordinator.isOAuthClientConfigured)
        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertEqual(authentication.clientSecretReadCount, 0)
        XCTAssertEqual(authentication.credentialReadCount, 0)
        XCTAssertEqual(coordinator.metadata.status, .failed)
        XCTAssertTrue(
            coordinator.metadata.statusMessage?.contains("configuration is required") == true
        )
    }

    @MainActor
    func testClientConfigurationChangeImmediatelyUpdatesCoordinatorState() {
        let authentication = FakeGoogleAuthentication(
            hasClientID: false,
            clientSecret: nil,
            hasCredential: false
        )
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: FakeGoogleTasksProvider(outcomes: [])
        )
        XCTAssertFalse(coordinator.isOAuthClientConfigured)

        authentication.hasClientID = true
        authentication.clientSecret = "newly-imported-secret"
        coordinator.clientConfigurationDidChange()

        XCTAssertTrue(coordinator.isClientIDConfigured)
        XCTAssertTrue(coordinator.isOAuthClientConfigured)
        XCTAssertEqual(coordinator.authenticationStatusMessage, "Not signed in to Google Tasks.")
    }

    @MainActor
    func testUnavailablePeriodicRefreshMarksCachedTasksStaleWithoutClaimingAttempt() {
        let previousAttempt = Date(timeIntervalSince1970: 800)
        let previousSuccess = Date(timeIntervalSince1970: 900)
        let authentication = FakeGoogleAuthentication(hasCredential: false)
        let provider = FakeGoogleTasksProvider(outcomes: [.success(.empty)])
        let taskRepository = InMemoryTaskRepository(tasks: [.incomplete(id: "cached")])
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository,
            metadataRepository: InMemorySyncMetadataRepository(
                metadata: SyncMetadata(
                    status: .current,
                    lastAttemptAt: previousAttempt,
                    lastSuccessfulRefreshAt: previousSuccess,
                    statusMessage: "Previously current"
                )
            )
        )

        coordinator.requestRefresh(.periodic)

        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(taskRepository.tasks.map(\.id), ["cached"])
        XCTAssertEqual(coordinator.metadata.status, .stale)
        XCTAssertEqual(coordinator.metadata.lastAttemptAt, previousAttempt)
        XCTAssertEqual(coordinator.metadata.lastSuccessfulRefreshAt, previousSuccess)
        XCTAssertTrue(coordinator.metadata.statusMessage?.contains("Sign in") == true)
    }

    @MainActor
    func testRetryableFailuresUseCappedExponentialBackoffThenReconcileCache() async {
        let provider = FakeGoogleTasksProvider(outcomes: [
            .failure(.transportFailure),
            .failure(.httpStatus(503)),
            .success(
                GoogleTasksSnapshot(
                    taskLists: [TaskList(id: "inbox", title: "Inbox")],
                    tasks: [TaskItem.incomplete(id: "fresh")]
                )
            ),
        ])
        let taskRepository = InMemoryTaskRepository(tasks: [.incomplete(id: "cached")])
        var delays: [TimeInterval] = []
        let coordinator = makeCoordinator(
            provider: provider,
            taskRepository: taskRepository,
            randomUnit: { 0.5 },
            sleeper: { delays.append($0) }
        )

        await coordinator.refresh(.manual)

        XCTAssertEqual(provider.callCount, 3)
        XCTAssertEqual(delays, [1, 2])
        XCTAssertEqual(taskRepository.tasks.map(\.id), ["fresh"])
        XCTAssertEqual(coordinator.metadata.status, .current)
    }

    @MainActor
    func testNetworkAPIDecodingFailuresRetainCachedTasksAndMarkExistingDataStale() async {
        let errors: [GoogleTasksError] = [
            .transportFailure,
            .httpStatus(400),
            .decodingFailed,
        ]

        for error in errors {
            let cachedTask = TaskItem.incomplete(id: "cached-offline")
            let taskRepository = InMemoryTaskRepository(tasks: [cachedTask])
            let metadataRepository = InMemorySyncMetadataRepository(
                metadata: SyncMetadata(
                    status: .current,
                    lastAttemptAt: Date(timeIntervalSince1970: 900),
                    lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 900),
                    statusMessage: "Previously current"
                )
            )
            let provider = FakeGoogleTasksProvider(outcomes: [.failure(error)])
            var cacheChangeCount = 0
            let coordinator = makeCoordinator(
                provider: provider,
                taskRepository: taskRepository,
                metadataRepository: metadataRepository,
                retryPolicy: GoogleTasksRetryPolicy(
                    maximumAttempts: 1,
                    baseDelay: 1,
                    maximumDelay: 1,
                    jitterFraction: 0
                ),
                cacheDidChange: { cacheChangeCount += 1 }
            )

            await coordinator.refresh(.manual)

            XCTAssertEqual(taskRepository.tasks, [cachedTask])
            XCTAssertEqual(taskRepository.replaceCount, 0)
            XCTAssertEqual(coordinator.metadata.status, .stale)
            XCTAssertTrue(
                coordinator.metadata.statusMessage?.contains("Cached tasks remain visible") == true
            )
            XCTAssertEqual(cacheChangeCount, 1)
        }
    }

    @MainActor
    func testSingleUnauthorizedResponseRefreshesTokenInsteadOfSigningOut() async {
        let authentication = FakeGoogleAuthentication(hasCredential: true)
        let taskRepository = InMemoryTaskRepository(tasks: [.incomplete(id: "cached")])
        let provider = FakeGoogleTasksProvider(outcomes: [
            .failure(.authenticationRequired),
            .success(.empty),
        ])
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository
        )

        await coordinator.refresh(.manual)

        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertEqual(authentication.signOutCount, 0)
        XCTAssertEqual(authentication.invalidateCount, 1)
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(coordinator.metadata.status, .current)
    }

    @MainActor
    func testRepeatedUnauthorizedResponseKeepsWorkingConnection() async {
        let authentication = FakeGoogleAuthentication(hasCredential: true)
        let taskRepository = InMemoryTaskRepository(tasks: [.incomplete(id: "cached")])
        let provider = FakeGoogleTasksProvider(outcomes: [
            .failure(.authenticationRequired),
            .failure(.authenticationRequired),
            .success(.empty),
        ])
        var expiredMessages: [String] = []
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository,
            authenticationDidExpire: { expiredMessages.append($0) }
        )

        await coordinator.refresh(.manual)

        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertEqual(authentication.signOutCount, 0)
        XCTAssertEqual(authentication.invalidateCount, 1)
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(taskRepository.tasks.map(\.id), ["cached"])
        XCTAssertEqual(coordinator.metadata.status, .failed)
        XCTAssertTrue(expiredMessages.isEmpty)
    }

    @MainActor
    func testRejectedRefreshTokenEndsSessionAndRequestsReauthentication() async {
        let authentication = FakeGoogleAuthentication(hasCredential: true)
        authentication.rejectsRefreshToken = true
        let taskRepository = InMemoryTaskRepository(tasks: [.incomplete(id: "cached")])
        let provider = FakeGoogleTasksProvider(outcomes: [.success(.empty)])
        var expiredMessages: [String] = []
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository,
            authenticationDidExpire: { expiredMessages.append($0) }
        )

        await coordinator.refresh(.manual)

        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(taskRepository.tasks.map(\.id), ["cached"])
        XCTAssertTrue(
            coordinator.authenticationStatusMessage.localizedCaseInsensitiveContains("again")
        )
        XCTAssertEqual(expiredMessages.count, 1)
    }

    @MainActor
    func testSessionEndExplanationReplacesGenericSignedOutMessage() async {
        let authentication = FakeGoogleAuthentication(hasCredential: true)
        authentication.sessionEndExplanation = "Google ended this session exactly a week after sign-in."
        authentication.rejectsRefreshToken = true
        let provider = FakeGoogleTasksProvider(outcomes: [])
        let coordinator = makeCoordinator(authentication: authentication, provider: provider)

        await coordinator.refresh(.manual)

        XCTAssertEqual(
            coordinator.authenticationStatusMessage,
            "Google ended this session exactly a week after sign-in."
        )
    }


    func testRetryPolicyCapsDelayAndAppliesDeterministicJitter() {
        let policy = GoogleTasksRetryPolicy(
            maximumAttempts: 5,
            baseDelay: 2,
            maximumDelay: 10,
            jitterFraction: 0.25
        )

        XCTAssertEqual(policy.delay(afterFailedAttempt: 1, randomUnit: 0.5), 2)
        XCTAssertEqual(policy.delay(afterFailedAttempt: 2, randomUnit: 0), 3)
        XCTAssertEqual(policy.delay(afterFailedAttempt: 8, randomUnit: 1), 10)
    }

    @MainActor
    private func makeCoordinator(
        authentication: FakeGoogleAuthentication = FakeGoogleAuthentication(),
        provider: FakeGoogleTasksProvider,
        taskRepository: InMemoryTaskRepository = InMemoryTaskRepository(),
        metadataRepository: InMemorySyncMetadataRepository = InMemorySyncMetadataRepository(),
        scheduler: FakePeriodicRefreshScheduler = FakePeriodicRefreshScheduler(),
        settingsRepository: InMemoryGoogleTasksSettingsRepository =
            InMemoryGoogleTasksSettingsRepository(),
        retryPolicy: GoogleTasksRetryPolicy = .defaultValue,
        randomUnit: @escaping @MainActor () -> Double = { 0.5 },
        sleeper: @escaping GoogleTasksSyncCoordinator.Sleeper = { _ in },
        cacheDidChange: @escaping @MainActor () -> Void = {},
        authenticationDidExpire: @escaping @MainActor (String) -> Void = { _ in }
    ) -> GoogleTasksSyncCoordinator {
        GoogleTasksSyncCoordinator(
            authentication: authentication,
            provider: provider,
            taskRepository: taskRepository,
            metadataRepository: metadataRepository,
            periodicScheduler: scheduler,
            settingsRepository: settingsRepository,
            retryPolicy: retryPolicy,
            randomUnit: randomUnit,
            sleeper: sleeper,
            cacheDidChange: cacheDidChange,
            authenticationDidExpire: authenticationDidExpire
        )
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 2_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Condition was not reached before timeout")
    }
}

@MainActor
private final class FakeGoogleAuthentication: GoogleTasksAuthenticating {
    var hasClientID: Bool
    var clientSecret: String?
    private var hasCredential: Bool
    private(set) var signInCount = 0
    private(set) var signOutCount = 0
    private(set) var accessTokenCount = 0
    private(set) var clientSecretReadCount = 0
    private(set) var credentialReadCount = 0
    private(set) var invalidateCount = 0
    var sessionEndExplanation: String?
    /// Simulates Google answering the refresh with `invalid_grant`: the OAuth service removes
    /// the credential and reports that sign-in is required.
    var rejectsRefreshToken = false

    init(
        hasClientID: Bool = true,
        clientSecret: String? = "configured-fake-client-secret",
        hasCredential: Bool = true
    ) {
        self.hasClientID = hasClientID
        self.clientSecret = clientSecret
        self.hasCredential = hasCredential
    }

    var isClientIDConfigured: Bool {
        hasClientID
    }

    var isConfigured: Bool {
        hasClientID && clientSecret?.isEmpty == false
    }

    func hasStoredClientSecret() throws -> Bool {
        clientSecretReadCount += 1
        return clientSecret != nil
    }

    func saveClientSecret(_ clientSecret: String) throws {
        self.clientSecret = clientSecret
    }

    func deleteClientSecret() throws {
        clientSecret = nil
    }

    func hasStoredCredential() throws -> Bool {
        credentialReadCount += 1
        return hasCredential
    }

    func signIn() async throws {
        signInCount += 1
        hasCredential = true
    }

    func invalidateAccessToken() {
        invalidateCount += 1
    }

    func signOut() throws {
        signOutCount += 1
        hasCredential = false
    }

    func validAccessToken() async throws -> String {
        accessTokenCount += 1
        if rejectsRefreshToken {
            hasCredential = false
        }
        guard hasCredential else {
            throw GoogleTasksError.authenticationRequired
        }
        return "access-token"
    }
}

@MainActor
private final class FakeGoogleTasksProvider: GoogleTasksProviding {
    var suspendFirstRequest = false
    private(set) var callCount = 0
    private(set) var maximumConcurrentRequestCount = 0
    private var activeRequestCount = 0
    private var outcomes: [Result<GoogleTasksSnapshot, GoogleTasksError>]
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?

    init(outcomes: [Result<GoogleTasksSnapshot, GoogleTasksError>]) {
        self.outcomes = outcomes
    }

    func fetchIncompleteTasks(accessToken: String) async throws -> GoogleTasksSnapshot {
        callCount += 1
        activeRequestCount += 1
        maximumConcurrentRequestCount = max(maximumConcurrentRequestCount, activeRequestCount)
        defer {
            activeRequestCount -= 1
        }

        if suspendFirstRequest, callCount == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
        }
        guard !outcomes.isEmpty else {
            return .empty
        }
        return try outcomes.removeFirst().get()
    }

    func resumeFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }
}

@MainActor
private final class InMemoryTaskRepository: TaskRepository {
    private(set) var taskLists: [TaskList]
    private(set) var tasks: [TaskItem]
    private(set) var replaceCount = 0

    init(taskLists: [TaskList] = [], tasks: [TaskItem] = []) {
        self.taskLists = taskLists
        self.tasks = tasks
    }

    func fetchIncompleteTasks() throws -> [TaskItem] {
        tasks.filter(\.isIncomplete)
    }

    func fetchTaskLists() throws -> [TaskList] {
        taskLists
    }

    func fetchTask(identifier: String) throws -> TaskItem? {
        tasks.first { $0.id == identifier }
    }

    func saveTask(_ task: TaskItem) throws {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    func replaceCache(taskLists: [TaskList], tasks: [TaskItem]) throws {
        replaceCount += 1
        self.taskLists = taskLists
        self.tasks = tasks
    }
}

@MainActor
private final class InMemorySyncMetadataRepository: SyncMetadataRepository {
    private var metadata: SyncMetadata?

    init(metadata: SyncMetadata? = nil) {
        self.metadata = metadata
    }

    func fetchMetadata() throws -> SyncMetadata? {
        metadata
    }

    func save(_ metadata: SyncMetadata) throws {
        self.metadata = metadata
    }
}

@MainActor
private final class FakePeriodicRefreshScheduler: GoogleTasksPeriodicRefreshScheduling {
    private(set) var interval: TimeInterval?
    private(set) var intervals: [TimeInterval] = []
    private(set) var stopCount = 0
    private var action: (@MainActor () -> Void)?

    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        intervals.append(interval)
        self.action = action
    }

    func stop() {
        stopCount += 1
        interval = nil
        action = nil
    }

    func fire() {
        action?()
    }
}

@MainActor
private final class InMemoryGoogleTasksSettingsRepository: GoogleTasksSettingsRepository {
    var settings: GoogleTasksSettings

    init(settings: GoogleTasksSettings = .defaultValue) {
        self.settings = settings
    }

    func fetchSettings() -> GoogleTasksSettings? { settings }
    func save(_ settings: GoogleTasksSettings) { self.settings = settings }
}

private extension GoogleTasksSnapshot {
    static let empty = GoogleTasksSnapshot(taskLists: [], tasks: [])
}

private extension TaskItem {
    static func incomplete(id: String) -> TaskItem {
        TaskItem(
            id: id,
            taskListID: "inbox",
            title: id,
            notes: nil,
            completionState: .incomplete,
            dueDate: nil,
            localTimeOverride: nil
        )
    }
}
