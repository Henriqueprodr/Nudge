import Foundation
import Observation

@MainActor
@Observable
final class GoogleTasksSyncCoordinator {
    static let defaultPeriodicInterval: TimeInterval = 15 * 60

    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void

    private let authentication: any GoogleTasksAuthenticating
    private let provider: any GoogleTasksProviding
    private let taskRepository: any TaskRepository
    private let metadataRepository: any SyncMetadataRepository
    private let periodicScheduler: any GoogleTasksPeriodicRefreshScheduling
    private let settingsRepository: any GoogleTasksSettingsRepository
    private let retryPolicy: GoogleTasksRetryPolicy
    private let now: @MainActor () -> Date
    private let randomUnit: @MainActor () -> Double
    private let sleeper: Sleeper
    private let cacheDidChange: @MainActor () -> Void
    private let authenticationDidExpire: @MainActor (String) -> Void
    private var refreshTask: Task<Void, Never>?
    private var followUpRefreshRequested = false
    private var hasStartedPeriodicRefresh = false
    private var settings: GoogleTasksSettings

    private(set) var metadata: SyncMetadata
    private(set) var isAuthenticated = false
    private(set) var isAuthenticating = false
    private(set) var isRefreshing = false
    private(set) var isClientIDConfigured = false
    private(set) var hasStoredClientSecret = false
    private(set) var hasBundledClientSecret = false
    private(set) var isOAuthClientConfigured = false
    private(set) var authenticationStatusMessage = ""

    private(set) var periodicInterval: TimeInterval

    init(
        authentication: any GoogleTasksAuthenticating,
        provider: any GoogleTasksProviding,
        taskRepository: any TaskRepository,
        metadataRepository: any SyncMetadataRepository,
        periodicScheduler: any GoogleTasksPeriodicRefreshScheduling,
        settingsRepository: any GoogleTasksSettingsRepository =
            UserDefaultsGoogleTasksSettingsRepository(),
        retryPolicy: GoogleTasksRetryPolicy = .defaultValue,
        periodicInterval: TimeInterval? = nil,
        now: @escaping @MainActor () -> Date = Date.init,
        randomUnit: @escaping @MainActor () -> Double = { Double.random(in: 0...1) },
        sleeper: @escaping Sleeper = { seconds in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        cacheDidChange: @escaping @MainActor () -> Void,
        authenticationDidExpire: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.authentication = authentication
        self.provider = provider
        self.taskRepository = taskRepository
        self.metadataRepository = metadataRepository
        self.periodicScheduler = periodicScheduler
        self.settingsRepository = settingsRepository
        self.retryPolicy = retryPolicy
        let restoredSettings = settingsRepository.fetchSettings() ?? .defaultValue
        settings = restoredSettings
        self.periodicInterval = periodicInterval
            ?? restoredSettings.periodicRefreshInterval.timeInterval
        self.now = now
        self.randomUnit = randomUnit
        self.sleeper = sleeper
        self.cacheDidChange = cacheDidChange
        self.authenticationDidExpire = authenticationDidExpire
        metadata = (try? metadataRepository.fetchMetadata()) ?? .initial

        refreshClientConfigurationState()
        if !isOAuthClientConfigured {
            authenticationStatusMessage = GoogleTasksError.configurationMissing.userMessage
        } else {
            authenticationStatusMessage = "Not signed in to Google Tasks."
        }
        if isOAuthClientConfigured {
            restoreAuthenticationState()
        }
        if isOAuthClientConfigured, !isAuthenticated,
           let explanation = authentication.sessionEndExplanation {
            authenticationStatusMessage = explanation
        }
        if !isAuthenticated {
            markRefreshUnavailable(message: unavailableRefreshMessage)
        }
    }

    func restoreAtLaunch() {
        periodicScheduler.start(interval: periodicInterval) { [weak self] in
            self?.requestRefresh(.periodic)
        }
        hasStartedPeriodicRefresh = true
        if isAuthenticated {
            requestRefresh(.launch)
        } else {
            markRefreshUnavailable(message: unavailableRefreshMessage)
        }
    }

    @discardableResult
    func signIn() async -> Bool {
        guard !isAuthenticating, isOAuthClientConfigured else {
            authenticationStatusMessage = GoogleTasksError.configurationMissing.userMessage
            return false
        }
        isAuthenticating = true
        authenticationStatusMessage = "Opening Google sign-in…"
        defer {
            isAuthenticating = false
        }
        do {
            try await authentication.signIn()
            isAuthenticated = true
            authenticationStatusMessage = "Signed in to Google Tasks."
            await refresh(.authentication)
            return true
        } catch {
            let normalizedError = GoogleTasksError.normalized(error)
            isAuthenticated = (try? authentication.hasStoredCredential()) == true
            authenticationStatusMessage = normalizedError.userMessage
            return false
        }
    }

    func signOut() {
        do {
            try authentication.signOut()
            isAuthenticated = false
            authenticationStatusMessage = "Not signed in. Cached tasks remain visible."
            markCacheStale(message: "Signed out. Cached tasks remain visible.")
        } catch {
            authenticationStatusMessage = GoogleTasksError.credentialStoreFailed.userMessage
        }
    }

    func accountDidAuthenticate() {
        refreshClientConfigurationState()
        restoreAuthenticationState()
        if isAuthenticated {
            requestRefresh(.authentication)
        }
    }

    func clientConfigurationDidChange() {
        refreshClientConfigurationState()
        restoreAuthenticationState()
        authenticationStatusMessage = isOAuthClientConfigured
            ? "Not signed in to Google Tasks."
            : GoogleTasksError.configurationMissing.userMessage
        if !isAuthenticated {
            markRefreshUnavailable(message: unavailableRefreshMessage)
        }
    }

    func setPeriodicRefreshInterval(_ interval: PeriodicRefreshInterval) {
        settings.periodicRefreshInterval = interval
        settingsRepository.save(settings)
        periodicInterval = interval.timeInterval
        guard hasStartedPeriodicRefresh else {
            return
        }
        periodicScheduler.stop()
        periodicScheduler.start(interval: periodicInterval) { [weak self] in
            self?.requestRefresh(.periodic)
        }
    }

    @discardableResult
    func saveClientSecret(_ clientSecret: String) -> Bool {
        guard !clientSecret.isEmpty else {
            authenticationStatusMessage = GoogleTasksError.configurationMissing.userMessage
            return false
        }
        do {
            try authentication.saveClientSecret(clientSecret)
            refreshClientConfigurationState()
            authenticationStatusMessage = isOAuthClientConfigured
                ? "Not signed in to Google Tasks."
                : GoogleTasksError.configurationMissing.userMessage
            return true
        } catch {
            refreshClientConfigurationState()
            authenticationStatusMessage = GoogleTasksError.credentialStoreFailed.userMessage
            return false
        }
    }

    func removeClientSecret() {
        guard !isAuthenticated else {
            return
        }
        do {
            try authentication.deleteClientSecret()
            refreshClientConfigurationState()
            authenticationStatusMessage = GoogleTasksError.configurationMissing.userMessage
        } catch {
            refreshClientConfigurationState()
            authenticationStatusMessage = GoogleTasksError.credentialStoreFailed.userMessage
        }
    }

    func requestRefresh(_ trigger: GoogleTasksRefreshTrigger) {
        guard isAuthenticated else {
            authenticationStatusMessage = isOAuthClientConfigured
                ? "Sign in to refresh Google Tasks."
                : GoogleTasksError.configurationMissing.userMessage
            markRefreshUnavailable(message: unavailableRefreshMessage)
            return
        }
        if refreshTask != nil {
            followUpRefreshRequested = true
            return
        }
        refreshTask = Task { @MainActor [weak self] in
            await self?.runRefreshLoop(initialTrigger: trigger)
        }
    }

    func refresh(_ trigger: GoogleTasksRefreshTrigger) async {
        requestRefresh(trigger)
        await refreshTask?.value
    }

    func requestRefreshAfterTaskMutation() {
        requestRefresh(.postAction)
    }

    func stop() {
        periodicScheduler.stop()
        hasStartedPeriodicRefresh = false
        refreshTask?.cancel()
        refreshTask = nil
        followUpRefreshRequested = false
        isRefreshing = false
    }

    private func restoreAuthenticationState() {
        do {
            isAuthenticated = try authentication.hasStoredCredential()
            if isAuthenticated {
                authenticationStatusMessage = isOAuthClientConfigured
                    ? "Signed in to Google Tasks."
                    : GoogleTasksError.configurationMissing.userMessage
            }
        } catch {
            isAuthenticated = false
            authenticationStatusMessage = GoogleTasksError.credentialStoreFailed.userMessage
        }
    }

    private func refreshClientConfigurationState() {
        isClientIDConfigured = authentication.isClientIDConfigured
        guard isClientIDConfigured else {
            hasStoredClientSecret = false
            hasBundledClientSecret = false
            isOAuthClientConfigured = false
            return
        }
        hasStoredClientSecret = (try? authentication.hasStoredClientSecret()) == true
        hasBundledClientSecret = authentication.hasBundledClientSecret
        isOAuthClientConfigured = authentication.isConfigured
    }

    private func runRefreshLoop(initialTrigger: GoogleTasksRefreshTrigger) async {
        var trigger = initialTrigger
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshTask = nil
        }

        while !Task.isCancelled {
            followUpRefreshRequested = false
            await performRefresh(trigger: trigger)
            guard followUpRefreshRequested, !Task.isCancelled, isAuthenticated else {
                return
            }
            trigger = .manual
        }
    }

    private func performRefresh(trigger: GoogleTasksRefreshTrigger) async {
        let attemptDate = now()
        metadata.lastAttemptAt = attemptDate
        if metadata.lastSuccessfulRefreshAt != nil {
            metadata.status = .stale
        }
        metadata.statusMessage = "Refreshing Google Tasks…"
        saveMetadataBestEffort()

        var failedAttempt = 0
        var hasRetriedAfterUnauthorizedResponse = false
        while failedAttempt < retryPolicy.maximumAttempts, !Task.isCancelled {
            var didObtainAccessToken = false
            do {
                let accessToken = try await authentication.validAccessToken()
                didObtainAccessToken = true
                let snapshot = try await provider.fetchIncompleteTasks(accessToken: accessToken)
                do {
                    try taskRepository.replaceCache(
                        taskLists: snapshot.taskLists,
                        tasks: snapshot.tasks
                    )
                } catch {
                    throw GoogleTasksError.persistenceFailure
                }

                metadata = SyncMetadata(
                    status: .current,
                    lastAttemptAt: attemptDate,
                    lastSuccessfulRefreshAt: now(),
                    statusMessage: "Updated \(snapshot.tasks.count) incomplete tasks."
                )
                saveMetadataBestEffort()
                authenticationStatusMessage = "Signed in to Google Tasks."
                cacheDidChange()
                return
            } catch {
                let normalizedError = GoogleTasksError.normalized(error)
                if normalizedError == .cancelled {
                    return
                }
                if normalizedError == .authenticationRequired {
                    // A 401 from the Tasks API with a locally valid token usually means the
                    // access token went stale (sleep, clock skew). Refresh it once before
                    // treating the session as ended, so the refresh token is never discarded
                    // for a recoverable failure.
                    if didObtainAccessToken, !hasRetriedAfterUnauthorizedResponse {
                        hasRetriedAfterUnauthorizedResponse = true
                        authentication.invalidateAccessToken()
                        continue
                    }
                    handleAuthenticationFailure()
                    return
                }

                failedAttempt += 1
                guard normalizedError.isRetryable,
                      failedAttempt < retryPolicy.maximumAttempts else {
                    markRefreshFailed(normalizedError)
                    return
                }
                let delay = retryPolicy.delay(
                    afterFailedAttempt: failedAttempt,
                    randomUnit: randomUnit()
                )
                do {
                    try await sleeper(delay)
                } catch {
                    return
                }
            }
        }
    }

    private func handleAuthenticationFailure() {
        // Only Google rejecting the refresh token ends the session, and `GoogleOAuthService`
        // removes the stored credential when that happens. If the credential is still here,
        // the connection is intact: keep it and let the next trigger retry.
        if (try? authentication.hasStoredCredential()) == true {
            markRefreshFailed(.httpStatus(401))
            return
        }
        isAuthenticated = false
        let message = authentication.sessionEndExplanation
            ?? GoogleTasksError.authenticationRequired.userMessage
        authenticationStatusMessage = message
        markCacheStale(message: message)
        authenticationDidExpire(message)
    }

    var signedInSince: Date? {
        isAuthenticated ? authentication.signedInSince : nil
    }

    private func markRefreshFailed(_ error: GoogleTasksError) {
        metadata.status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        metadata.statusMessage = error.userMessage
        saveMetadataBestEffort()
        cacheDidChange()
    }

    private func markCacheStale(message: String) {
        metadata.status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        metadata.statusMessage = message
        saveMetadataBestEffort()
        cacheDidChange()
    }

    private var unavailableRefreshMessage: String {
        if isOAuthClientConfigured {
            return "Sign in to refresh Google Tasks. Cached tasks remain visible."
        }
        return "Google OAuth client configuration is required. Cached tasks remain visible."
    }

    private func markRefreshUnavailable(message: String) {
        let status: SyncMetadata.Status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        guard metadata.status != status || metadata.statusMessage != message else {
            return
        }
        metadata.status = status
        metadata.statusMessage = message
        saveMetadataBestEffort()
        cacheDidChange()
    }

    private func saveMetadataBestEffort() {
        try? metadataRepository.save(metadata)
    }
}
