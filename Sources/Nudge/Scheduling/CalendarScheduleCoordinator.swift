import Foundation
import Observation

@MainActor
@Observable
final class GoogleCalendarSyncCoordinator {
    static let defaultPeriodicInterval: TimeInterval = 5 * 60
    static let maximumEventCount = 10_000

    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void

    private static let missedReminderLookBehind: TimeInterval = 15 * 60
    private static let maximumGoogleReminderOffset: TimeInterval = 28 * 24 * 60 * 60

    private let authentication: any GoogleScopeAuthenticating
    private let provider: any GoogleCalendarProviding
    private let cacheRepository: any CalendarCacheRepository
    private let settingsRepository: any CalendarSettingsRepository
    private weak var reminderConsumer: (any CalendarReminderConsumer)?
    private let periodicScheduler: any GoogleCalendarPeriodicRefreshScheduling
    private let notificationFallback: (any ReminderNotificationFallbackProviding)?
    private let retryPolicy: GoogleCalendarRetryPolicy
    private let now: @MainActor () -> Date
    private let randomUnit: @MainActor () -> Double
    private let sleeper: Sleeper
    private var settings: CalendarSettings
    private var refreshTask: Task<Void, Never>?
    private var followUpRefreshRequested = false
    private var hasStartedPeriodicRefresh = false

    private(set) var calendars: [CalendarDescriptor] = []
    private(set) var metadata: SyncMetadata
    private(set) var isRefreshing = false
    private(set) var isAuthenticating = false
    private(set) var hasCalendarAuthorization = false
    private(set) var hasStoredGoogleCredential = false
    private(set) var statusMessage = "Google Calendar is not connected."
    private(set) var notificationFallbackStatusMessage = "Notification fallback is off."

    private(set) var periodicInterval: TimeInterval

    /// Called when Google ends the shared session so the app can ask the user to sign in.
    @ObservationIgnored var onAuthenticationExpired: (@MainActor (String) -> Void)?

    init(
        authentication: any GoogleScopeAuthenticating,
        provider: any GoogleCalendarProviding,
        cacheRepository: any CalendarCacheRepository,
        settingsRepository: any CalendarSettingsRepository,
        reminderConsumer: any CalendarReminderConsumer,
        periodicScheduler: any GoogleCalendarPeriodicRefreshScheduling,
        notificationFallback: (any ReminderNotificationFallbackProviding)? = nil,
        retryPolicy: GoogleCalendarRetryPolicy = .defaultValue,
        periodicInterval: TimeInterval? = nil,
        now: @escaping @MainActor () -> Date = Date.init,
        randomUnit: @escaping @MainActor () -> Double = { Double.random(in: 0...1) },
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.authentication = authentication
        self.provider = provider
        self.cacheRepository = cacheRepository
        self.settingsRepository = settingsRepository
        self.reminderConsumer = reminderConsumer
        self.periodicScheduler = periodicScheduler
        self.notificationFallback = notificationFallback
        self.retryPolicy = retryPolicy
        self.now = now
        self.randomUnit = randomUnit
        self.sleeper = sleeper
        let restoredSettings = settingsRepository.fetchSettings() ?? .defaultValue
        settings = restoredSettings
        self.periodicInterval = periodicInterval
            ?? restoredSettings.periodicRefreshInterval.timeInterval
        metadata = (try? cacheRepository.fetchMetadata()) ?? .initial
        migrateLegacySettingsIfNeeded()
        refreshAuthorizationState()
    }

    var selectedCalendarIdentifiers: Set<String> {
        settings.selectedCalendarIdentifiers
    }

    var usesNotificationFallback: Bool {
        settings.usesNotificationFallback
    }

    var needsScopeUpgrade: Bool {
        authentication.isConfigured && hasStoredGoogleCredential && !hasCalendarAuthorization
    }

    func restoreAtLaunch() async {
        if settings.usesNotificationFallback, let notificationFallback {
            _ = await notificationFallback.requestAuthorization()
            notificationFallbackStatusMessage = notificationFallback.statusMessage
        }
        do {
            calendars = try cacheRepository.fetchCalendars()
            applyDefaultSelectionIfNeeded()
            try rebuildSchedule(from: cacheRepository.fetchEvents())
        } catch {
            statusMessage = "Cached Calendar reminders could not be restored."
        }
        periodicScheduler.start(interval: periodicInterval) { [weak self] in
            self?.requestRefresh(.periodic)
        }
        hasStartedPeriodicRefresh = true
        refreshAuthorizationState()
        if hasCalendarAuthorization {
            requestRefresh(.launch)
        } else {
            markAuthorizationUnavailable(message: unavailableAuthorizationMessage)
        }
    }

    @discardableResult
    func signInWithGoogle() async -> Bool {
        guard !isAuthenticating, authentication.isConfigured else {
            statusMessage = "Google OAuth client configuration is required."
            return false
        }
        isAuthenticating = true
        statusMessage = "Opening Google sign-in…"
        defer { isAuthenticating = false }
        do {
            try await authentication.signIn(
                requestingFullScopeUnion: GoogleOAuthConfiguration.requiredScopeUnion
            )
            refreshAuthorizationState()
            await refresh(.authentication)
            return true
        } catch {
            refreshAuthorizationState()
            statusMessage = (error as? GoogleOAuthError)?.userMessage
                ?? "Google Calendar access was not granted. Existing cached data was preserved."
            return false
        }
    }

    func accountDidAuthenticate() {
        refreshAuthorizationState()
        if hasCalendarAuthorization { requestRefresh(.authentication) }
    }

    func accountDidDisconnect() {
        refreshAuthorizationState()
        metadata.status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        metadata.statusMessage = "Signed out. Cached Calendar reminders remain available."
        saveMetadataBestEffort()
        statusMessage = metadata.statusMessage ?? statusMessage
    }

    func clientConfigurationDidChange() {
        refreshAuthorizationState()
        if !authentication.isConfigured {
            statusMessage = "Google OAuth client configuration is required."
        } else if !hasStoredGoogleCredential {
            statusMessage = "Google Calendar is not connected."
        }
    }

    func setCalendar(_ identifier: String, isSelected: Bool) async {
        settings.hasConfiguredSelection = true
        if isSelected {
            settings.selectedCalendarIdentifiers.insert(identifier)
        } else {
            settings.selectedCalendarIdentifiers.remove(identifier)
        }
        settingsRepository.save(settings)
        rebuildFromCacheBestEffort()
        requestRefresh(.settingsChange)
    }

    func setUsesNotificationFallback(_ isEnabled: Bool) async {
        if isEnabled, let notificationFallback,
           await !notificationFallback.requestAuthorization() {
            statusMessage = notificationFallback.statusMessage
            notificationFallbackStatusMessage = notificationFallback.statusMessage
            return
        }
        settings.usesNotificationFallback = isEnabled
        settingsRepository.save(settings)
        notificationFallbackStatusMessage = isEnabled
            ? notificationFallback?.statusMessage ?? "Notification fallback is enabled."
            : "Notification fallback is off."
        rebuildFromCacheBestEffort()
        requestRefresh(.settingsChange)
    }

    func setPeriodicRefreshInterval(_ interval: PeriodicRefreshInterval) {
        settings.periodicRefreshInterval = interval
        settings.schemaVersion = max(settings.schemaVersion, 3)
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

    func refreshSchedule() async {
        await refresh(.manual)
    }

    func recoverScheduleFromCache() {
        rebuildFromCacheBestEffort()
    }

    func requestRefresh(_ trigger: GoogleCalendarRefreshTrigger) {
        refreshAuthorizationState()
        guard hasCalendarAuthorization else {
            markAuthorizationUnavailable(message: unavailableAuthorizationMessage)
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

    func refresh(_ trigger: GoogleCalendarRefreshTrigger) async {
        requestRefresh(trigger)
        await refreshTask?.value
    }

    func stop() {
        periodicScheduler.stop()
        hasStartedPeriodicRefresh = false
        refreshTask?.cancel()
        refreshTask = nil
        followUpRefreshRequested = false
        isRefreshing = false
    }

    private func runRefreshLoop(initialTrigger: GoogleCalendarRefreshTrigger) async {
        var trigger = initialTrigger
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshTask = nil
        }
        while !Task.isCancelled {
            let followUpAlreadyRequested = followUpRefreshRequested
            followUpRefreshRequested = false
            await performRefresh(trigger: trigger)
            let shouldRunFollowUp = followUpAlreadyRequested || followUpRefreshRequested
            followUpRefreshRequested = false
            guard shouldRunFollowUp, !Task.isCancelled, hasCalendarAuthorization else {
                return
            }
            trigger = .manual
        }
    }

    private func performRefresh(trigger: GoogleCalendarRefreshTrigger) async {
        let attemptDate = now()
        metadata.lastAttemptAt = attemptDate
        if metadata.lastSuccessfulRefreshAt != nil { metadata.status = .stale }
        metadata.statusMessage = "Refreshing Google Calendar…"
        saveMetadataBestEffort()

        var failedAttempt = 0
        var hasRetriedAfterUnauthorizedResponse = false
        while failedAttempt < retryPolicy.maximumAttempts, !Task.isCancelled {
            var didObtainAccessToken = false
            do {
                let token = try await authentication.validAccessToken(
                    requiredScopes: GoogleOAuthConfiguration.calendarReadScopes
                )
                didObtainAccessToken = true
                let fetchedCalendars = try await provider.fetchCalendars(accessToken: token)
                do {
                    try cacheRepository.replaceCalendars(fetchedCalendars)
                } catch {
                    throw GoogleCalendarError.persistenceFailure
                }
                calendars = fetchedCalendars
                applyDefaultSelectionIfNeeded()

                let currentDate = now()
                let reminderHorizon = TimeInterval(settings.lookAheadDays * 24 * 60 * 60)
                let queryInterval = DateInterval(
                    start: currentDate.addingTimeInterval(-Self.missedReminderLookBehind),
                    end: currentDate.addingTimeInterval(
                        reminderHorizon + Self.maximumGoogleReminderOffset
                    )
                )
                let selected = calendars.filter {
                    settings.selectedCalendarIdentifiers.contains($0.id)
                }
                var events: [CalendarEventSnapshot] = []
                for calendar in selected {
                    try Task.checkCancellation()
                    events.append(
                        contentsOf: try await provider.fetchEvents(
                            calendar: calendar,
                            in: queryInterval,
                            accessToken: token
                        )
                    )
                    guard events.count <= Self.maximumEventCount else {
                        throw GoogleCalendarError.snapshotTooLarge
                    }
                }
                do {
                    try cacheRepository.replaceEvents(events)
                    try rebuildSchedule(from: events)
                } catch let error as GoogleCalendarError {
                    throw error
                } catch {
                    throw GoogleCalendarError.persistenceFailure
                }
                let successfulStatusMessage = statusMessage
                metadata = SyncMetadata(
                    status: .current,
                    lastAttemptAt: attemptDate,
                    lastSuccessfulRefreshAt: now(),
                    statusMessage: successfulStatusMessage
                )
                saveMetadataBestEffort()
                statusMessage = successfulStatusMessage
                return
            } catch {
                let normalized = normalize(error)
                if normalized == .cancelled { return }
                if normalized == .authenticationRequired, didObtainAccessToken,
                   !hasRetriedAfterUnauthorizedResponse {
                    // Refresh a stale access token once before treating the session as ended.
                    hasRetriedAfterUnauthorizedResponse = true
                    authentication.invalidateAccessToken()
                    continue
                }
                if normalized == .authenticationRequired || normalized == .authorizationRequired {
                    hasCalendarAuthorization = false
                    markRefreshFailed(normalized)
                    if normalized == .authenticationRequired {
                        onAuthenticationExpired?(normalized.userMessage)
                    }
                    return
                }
                failedAttempt += 1
                guard normalized.isRetryable,
                      failedAttempt < retryPolicy.maximumAttempts else {
                    markRefreshFailed(normalized)
                    return
                }
                do {
                    try await sleeper(
                        retryPolicy.delay(
                            afterFailedAttempt: failedAttempt,
                            randomUnit: randomUnit()
                        )
                    )
                } catch {
                    return
                }
            }
        }
    }

    private func rebuildSchedule(from events: [CalendarEventSnapshot]) throws {
        let currentDate = now()
        let interval = DateInterval(
            start: currentDate.addingTimeInterval(-Self.missedReminderLookBehind),
            end: currentDate.addingTimeInterval(
                TimeInterval(settings.lookAheadDays * 24 * 60 * 60)
            )
        )
        let mapper = CalendarReminderMapper()
        let reminders = events
            .filter { settings.selectedCalendarIdentifiers.contains($0.calendarIdentifier) }
            .flatMap(mapper.reminders(from:))
            .filter { interval.contains($0.triggerDate) }
            .map { reminder in
                Reminder(
                    occurrenceID: reminder.occurrenceID,
                    title: reminder.title,
                    detail: reminder.detail,
                    triggerDate: reminder.triggerDate,
                    expirationDate: reminder.expirationDate,
                    presentationMode: settings.usesNotificationFallback
                        ? .overlayWithNotificationFallback
                        : .overlay,
                    sourceURL: reminder.sourceURL,
                    eventContext: reminder.eventContext
                )
            }
        try reminderConsumer?.replaceCalendarReminders(with: reminders)
        if calendars.isEmpty {
            statusMessage = "No Google calendars are available for this account."
        } else if settings.selectedCalendarIdentifiers.isEmpty {
            statusMessage = "No Google calendars are selected."
        } else {
            statusMessage = reminders.isEmpty
                ? "No upcoming reminders in the selected Google calendars."
                : "Google Calendar reminders are scheduled."
        }
    }

    private func applyDefaultSelectionIfNeeded() {
        let available = Set(calendars.map(\.id))
        if settings.hasConfiguredSelection {
            settings.selectedCalendarIdentifiers.formIntersection(available)
        } else {
            var defaults = Set(
                calendars.filter(\.isSelectedInGoogleCalendar).map(\.id)
            )
            if defaults.isEmpty, let primary = calendars.first(where: \.isPrimary) {
                defaults.insert(primary.id)
            }
            settings.selectedCalendarIdentifiers = defaults
            settings.hasConfiguredSelection = true
        }
        settingsRepository.save(settings)
    }

    private func migrateLegacySettingsIfNeeded() {
        var didChange = false
        if settings.schemaVersion < 2 {
            settings.selectedCalendarIdentifiers = []
            settings.hasConfiguredSelection = false
            didChange = true
        }
        if settings.schemaVersion < 3 {
            settings.periodicRefreshInterval = CalendarSettings.defaultPeriodicRefreshInterval
            didChange = true
        }
        guard didChange else { return }
        settings.schemaVersion = 3
        settingsRepository.save(settings)
    }

    private func rebuildFromCacheBestEffort() {
        do {
            try rebuildSchedule(from: cacheRepository.fetchEvents())
        } catch {
            statusMessage = "Cached Calendar reminders could not be rebuilt."
        }
    }

    private func refreshAuthorizationState() {
        guard authentication.isConfigured else {
            hasCalendarAuthorization = false
            hasStoredGoogleCredential = false
            markAuthorizationUnavailable(message: unavailableAuthorizationMessage)
            return
        }
        hasStoredGoogleCredential = (
            try? authentication.hasStoredCredential(requiredScopes: [])
        ) == true
        hasCalendarAuthorization = (
            try? authentication.hasStoredCredential(
                requiredScopes: GoogleOAuthConfiguration.calendarReadScopes
            )
        ) == true
        if !hasCalendarAuthorization {
            markAuthorizationUnavailable(message: unavailableAuthorizationMessage)
        }
    }

    private var unavailableAuthorizationMessage: String {
        if !authentication.isConfigured {
            return "Google OAuth client configuration is required. Cached Calendar reminders remain available."
        }
        if hasStoredGoogleCredential {
            return "Add Google Calendar access. Cached Calendar reminders remain available."
        }
        return "Sign in to refresh Google Calendar. Cached Calendar reminders remain available."
    }

    private func markAuthorizationUnavailable(message: String) {
        let status: SyncMetadata.Status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        if metadata.status != status || metadata.statusMessage != message {
            metadata.status = status
            metadata.statusMessage = message
            saveMetadataBestEffort()
        }
        statusMessage = message
    }

    private func normalize(_ error: Error) -> GoogleCalendarError {
        if let oauthError = error as? GoogleOAuthError {
            switch oauthError {
            case .authenticationRequired:
                return .authenticationRequired
            case .cancelled:
                return .cancelled
            default:
                return .invalidResponse
            }
        }
        return GoogleCalendarError.normalized(error)
    }

    private func markRefreshFailed(_ error: GoogleCalendarError) {
        metadata.status = metadata.lastSuccessfulRefreshAt == nil ? .failed : .stale
        metadata.statusMessage = error.userMessage
        saveMetadataBestEffort()
        statusMessage = error.userMessage
    }

    private func saveMetadataBestEffort() {
        try? cacheRepository.saveMetadata(metadata)
    }
}

typealias CalendarScheduleCoordinator = GoogleCalendarSyncCoordinator
