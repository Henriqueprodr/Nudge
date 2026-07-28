import Foundation
import XCTest
@testable import Nudge

final class CalendarScheduleCoordinatorTests: XCTestCase {
    @MainActor
    func testLaunchRestoresCacheStartsFiveMinuteTimerAndRefreshes() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let cachedEvent = makeEvent(now: now)
        let cache = InMemoryCalendarCache(calendars: [calendar], events: [cachedEvent])
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [cachedEvent])
        let consumer = RecordingCalendarReminderConsumer()
        let timer = RecordingCalendarTimer()
        let coordinator = makeCoordinator(
            provider: provider,
            cache: cache,
            consumer: consumer,
            timer: timer,
            now: now
        )

        await coordinator.restoreAtLaunch()
        await coordinator.refresh(.manual)

        XCTAssertEqual(timer.intervals, [300])
        XCTAssertFalse(consumer.replacements.first?.isEmpty ?? true)
        XCTAssertGreaterThanOrEqual(provider.calendarFetchCount, 1)
        let fetchCountBeforePeriodicTrigger = provider.calendarFetchCount
        timer.fire()
        for _ in 0..<100 where provider.calendarFetchCount == fetchCountBeforePeriodicTrigger {
            await Task.yield()
        }
        XCTAssertEqual(provider.calendarFetchCount, fetchCountBeforePeriodicTrigger + 1)
        coordinator.stop()
    }

    @MainActor
    func testScheduledReminderPreservesCalendarEventStartTime() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let event = makeEvent(now: now)
        let cache = InMemoryCalendarCache(calendars: [calendar], events: [event])
        let consumer = RecordingCalendarReminderConsumer()
        let coordinator = makeCoordinator(cache: cache, consumer: consumer, now: now)

        await coordinator.restoreAtLaunch()

        let reminder = try XCTUnwrap(consumer.replacements.last?.first)
        XCTAssertEqual(reminder.triggerDate, now)
        XCTAssertEqual(reminder.eventContext?.startDate, event.startDate)
        XCTAssertNotEqual(reminder.eventContext?.startDate, reminder.triggerDate)
        coordinator.stop()
    }

    @MainActor
    func testRefreshUsesSelectedCalendarAndFortyTwoDayBoundedQuery() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let selected = makeCalendar(id: "selected", selected: true)
        let other = makeCalendar(id: "other", selected: false)
        let provider = FakeGoogleCalendarProvider(calendars: [selected, other], events: [])
        let coordinator = makeCoordinator(provider: provider, now: now)

        await coordinator.refresh(.manual)

        XCTAssertEqual(provider.eventCalendarIDs, ["selected"])
        let interval = try XCTUnwrap(provider.intervals.first)
        XCTAssertEqual(interval.start, now.addingTimeInterval(-15 * 60))
        XCTAssertEqual(interval.end, now.addingTimeInterval(42 * 24 * 60 * 60))
        coordinator.stop()
    }

    @MainActor
    func testEventFailurePreservesLastSuccessfulCacheAndMarksItStale() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let cached = makeEvent(now: now)
        let cache = InMemoryCalendarCache(
            calendars: [calendar],
            events: [cached],
            metadata: SyncMetadata(
                status: .current,
                lastAttemptAt: now,
                lastSuccessfulRefreshAt: now,
                statusMessage: nil
            )
        )
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [])
        provider.eventError = GoogleCalendarError.httpStatus(500)
        let coordinator = makeCoordinator(provider: provider, cache: cache, now: now)

        await coordinator.refresh(.manual)

        XCTAssertEqual(cache.events, [cached])
        XCTAssertEqual(cache.metadata?.status, .stale)
        XCTAssertEqual(provider.eventFetchCount, 3)
        coordinator.stop()
    }

    @MainActor
    func testSuccessfulEmptySnapshotClearsCalendarReminders() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let cache = InMemoryCalendarCache(calendars: [calendar], events: [makeEvent(now: now)])
        let consumer = RecordingCalendarReminderConsumer()
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [])
        let coordinator = makeCoordinator(
            provider: provider,
            cache: cache,
            consumer: consumer,
            now: now
        )

        await coordinator.refresh(.manual)

        XCTAssertTrue(cache.events.isEmpty)
        XCTAssertEqual(consumer.replacements.last, [])
        coordinator.stop()
    }

    @MainActor
    func testClientConfigurationChangeImmediatelyUpdatesCalendarState() {
        let authentication = FakeGoogleScopeAuthentication(hasCredential: false)
        authentication.isConfigured = false
        let coordinator = makeCoordinator(authentication: authentication)
        XCTAssertTrue(coordinator.statusMessage.contains("configuration is required"))

        authentication.isConfigured = true
        coordinator.clientConfigurationDidChange()

        XCTAssertEqual(coordinator.statusMessage, "Google Calendar is not connected.")
        XCTAssertFalse(coordinator.hasStoredGoogleCredential)
        XCTAssertFalse(coordinator.hasCalendarAuthorization)
    }

    @MainActor
    func testSuccessfulEmptyCalendarListClearsCachesAndReportsInformativeState() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let cache = InMemoryCalendarCache(
            calendars: [calendar],
            events: [makeEvent(now: now)]
        )
        let consumer = RecordingCalendarReminderConsumer()
        let provider = FakeGoogleCalendarProvider(calendars: [], events: [])
        let coordinator = makeCoordinator(
            provider: provider,
            cache: cache,
            consumer: consumer,
            now: now
        )

        await coordinator.refresh(.manual)

        XCTAssertTrue(coordinator.calendars.isEmpty)
        XCTAssertTrue(cache.calendars.isEmpty)
        XCTAssertTrue(cache.events.isEmpty)
        XCTAssertEqual(consumer.replacements.last, [])
        XCTAssertEqual(provider.eventFetchCount, 0)
        XCTAssertEqual(
            coordinator.statusMessage,
            "No Google calendars are available for this account."
        )
        XCTAssertEqual(cache.metadata?.status, .current)
        XCTAssertEqual(cache.metadata?.statusMessage, coordinator.statusMessage)
        coordinator.stop()
    }

    @MainActor
    func testOversizedSuccessfulSnapshotPreservesLastSuccessfulEventCache() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let cached = makeEvent(now: now)
        let cache = InMemoryCalendarCache(calendars: [calendar], events: [cached])
        let provider = FakeGoogleCalendarProvider(
            calendars: [calendar],
            events: Array(repeating: makeEvent(now: now), count: 10_001)
        )
        let coordinator = makeCoordinator(provider: provider, cache: cache, now: now)

        await coordinator.refresh(.manual)

        XCTAssertEqual(cache.events, [cached])
        XCTAssertEqual(cache.metadata?.status, .failed)
        XCTAssertEqual(provider.eventFetchCount, 1)
        coordinator.stop()
    }

    @MainActor
    func testDuplicateTriggersAllowOneActiveRefreshAndOneFollowUp() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [])
        provider.delayNanoseconds = 40_000_000
        let coordinator = makeCoordinator(provider: provider, now: now)

        coordinator.requestRefresh(.manual)
        coordinator.requestRefresh(.wake)
        coordinator.requestRefresh(.settingsChange)
        try? await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(provider.calendarFetchCount, 2)
        XCTAssertEqual(provider.maximumConcurrentFetches, 1)
        coordinator.stop()
    }

    @MainActor
    func testLegacySelectionMigrationPreservesLookAheadAndFallback() {
        let settings = CalendarSettings(
            schemaVersion: 1,
            selectedCalendarIdentifiers: ["legacy-apple-id"],
            hasConfiguredSelection: true,
            lookAheadDays: 9,
            usesNotificationFallback: true
        )
        let repository = InMemoryCalendarSettingsRepository(settings: settings)
        let coordinator = makeCoordinator(settings: repository)

        XCTAssertEqual(repository.settings?.schemaVersion, 3)
        XCTAssertEqual(repository.settings?.selectedCalendarIdentifiers, [])
        XCTAssertEqual(repository.settings?.lookAheadDays, 9)
        XCTAssertEqual(repository.settings?.usesNotificationFallback, true)
        XCTAssertEqual(
            repository.settings?.periodicRefreshInterval,
            CalendarSettings.defaultPeriodicRefreshInterval
        )
        coordinator.stop()
    }

    @MainActor
    func testMissingCalendarScopeMarksCacheStaleWithoutClaimingProviderAttempt() async {
        let previousAttempt = Date(timeIntervalSince1970: 800)
        let previousSuccess = Date(timeIntervalSince1970: 900)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let event = makeEvent(now: now)
        let cache = InMemoryCalendarCache(
            calendars: [calendar],
            events: [event],
            metadata: SyncMetadata(
                status: .current,
                lastAttemptAt: previousAttempt,
                lastSuccessfulRefreshAt: previousSuccess,
                statusMessage: "Previously current"
            )
        )
        let authentication = FakeGoogleScopeAuthentication(
            grantedScopes: [GoogleOAuthConfiguration.tasksScope]
        )
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [event])
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            cache: cache,
            now: now
        )

        await coordinator.restoreAtLaunch()
        coordinator.requestRefresh(.periodic)

        XCTAssertTrue(coordinator.needsScopeUpgrade)
        XCTAssertEqual(provider.calendarFetchCount, 0)
        XCTAssertEqual(cache.events, [event])
        XCTAssertEqual(coordinator.metadata.status, .stale)
        XCTAssertEqual(coordinator.metadata.lastAttemptAt, previousAttempt)
        XCTAssertEqual(coordinator.metadata.lastSuccessfulRefreshAt, previousSuccess)
        XCTAssertTrue(coordinator.statusMessage.contains("Add Google Calendar access"))
        coordinator.stop()
    }

    @MainActor
    func testNoStoredCredentialRequestsSignInInsteadOfScopeUpgrade() {
        let authentication = FakeGoogleScopeAuthentication(hasCredential: false)
        let coordinator = makeCoordinator(authentication: authentication)

        XCTAssertFalse(coordinator.needsScopeUpgrade)
        XCTAssertEqual(coordinator.metadata.status, .failed)
        XCTAssertTrue(coordinator.statusMessage.contains("Sign in"))
        coordinator.stop()
    }

    @MainActor
    func testScopeExpansionImmediatelyRefreshesCalendar() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let calendar = makeCalendar()
        let authentication = FakeGoogleScopeAuthentication(
            grantedScopes: [GoogleOAuthConfiguration.tasksScope]
        )
        let provider = FakeGoogleCalendarProvider(calendars: [calendar], events: [])
        let coordinator = makeCoordinator(
            authentication: authentication,
            provider: provider,
            now: now
        )

        let succeeded = await coordinator.signInWithGoogle()

        XCTAssertTrue(succeeded)
        XCTAssertTrue(coordinator.hasCalendarAuthorization)
        XCTAssertEqual(provider.calendarFetchCount, 1)
        XCTAssertEqual(coordinator.metadata.status, .current)
        coordinator.stop()
    }

    @MainActor
    func testPeriodicIntervalRestoresAndReschedulesOnlyCalendarTimer() async {
        let timer = RecordingCalendarTimer()
        let settings = InMemoryCalendarSettingsRepository(
            settings: CalendarSettings(
                schemaVersion: 3,
                selectedCalendarIdentifiers: [],
                hasConfiguredSelection: false,
                lookAheadDays: 14,
                usesNotificationFallback: false,
                periodicRefreshInterval: PeriodicRefreshInterval(minutes: 60)
            )
        )
        let coordinator = makeCoordinator(timer: timer, settings: settings)

        await coordinator.restoreAtLaunch()
        coordinator.setPeriodicRefreshInterval(PeriodicRefreshInterval(minutes: 5))

        XCTAssertEqual(timer.intervals, [3_600, 300])
        XCTAssertEqual(timer.stopCount, 1)
        XCTAssertEqual(coordinator.periodicInterval, 300)
        XCTAssertEqual(settings.settings?.periodicRefreshInterval.minutes, 5)
        coordinator.stop()
    }

    @MainActor
    func testNotificationFallbackPermissionDenialIsExplicitAndLeavesSettingOff() async {
        let settings = InMemoryCalendarSettingsRepository()
        let fallback = DeniedCalendarNotificationFallback()
        let coordinator = makeCoordinator(settings: settings, notificationFallback: fallback)

        await coordinator.setUsesNotificationFallback(true)

        XCTAssertFalse(coordinator.usesNotificationFallback)
        XCTAssertEqual(fallback.authorizationRequestCount, 1)
        XCTAssertEqual(coordinator.notificationFallbackStatusMessage, fallback.statusMessage)
        XCTAssertEqual(coordinator.statusMessage, fallback.statusMessage)
        coordinator.stop()
    }

    @MainActor
    private func makeCoordinator(
        authentication: FakeGoogleScopeAuthentication = FakeGoogleScopeAuthentication(),
        provider: FakeGoogleCalendarProvider = FakeGoogleCalendarProvider(calendars: [], events: []),
        cache: InMemoryCalendarCache = InMemoryCalendarCache(),
        consumer: RecordingCalendarReminderConsumer = RecordingCalendarReminderConsumer(),
        timer: RecordingCalendarTimer = RecordingCalendarTimer(),
        settings: InMemoryCalendarSettingsRepository = InMemoryCalendarSettingsRepository(),
        notificationFallback: (any ReminderNotificationFallbackProviding)? = nil,
        now: Date = Date()
    ) -> GoogleCalendarSyncCoordinator {
        GoogleCalendarSyncCoordinator(
            authentication: authentication,
            provider: provider,
            cacheRepository: cache,
            settingsRepository: settings,
            reminderConsumer: consumer,
            periodicScheduler: timer,
            notificationFallback: notificationFallback,
            now: { now },
            randomUnit: { 0.5 },
            sleeper: { _ in }
        )
    }
}

@MainActor
private final class DeniedCalendarNotificationFallback: ReminderNotificationFallbackProviding {
    private(set) var authorizationRequestCount = 0
    let statusMessage = "Notification permission was not granted; overlays remain enabled."

    func setSoundEnabled(_ isEnabled: Bool) {}

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        return false
    }

    func deliver(_ reminder: Reminder) async -> Bool { false }
}

@MainActor
private final class FakeGoogleScopeAuthentication: GoogleScopeAuthenticating {
    var isClientIDConfigured = true
    var isConfigured = true
    private var hasCredential: Bool
    var grantedScopes: Set<String>

    init(
        hasCredential: Bool = true,
        grantedScopes: Set<String> = GoogleOAuthConfiguration.requiredScopeUnion
    ) {
        self.hasCredential = hasCredential
        self.grantedScopes = grantedScopes
    }

    func hasStoredCredential(requiredScopes: Set<String>) throws -> Bool {
        hasCredential && requiredScopes.isSubset(of: grantedScopes)
    }

    func signIn(requestingFullScopeUnion scopes: Set<String>) async throws {
        hasCredential = true
        grantedScopes = scopes
    }

    func validAccessToken(requiredScopes: Set<String>) async throws -> String {
        guard requiredScopes.isSubset(of: grantedScopes) else {
            throw GoogleOAuthError.authenticationRequired
        }
        return "test-access-token"
    }
}

@MainActor
private final class FakeGoogleCalendarProvider: GoogleCalendarProviding {
    var calendars: [CalendarDescriptor]
    var events: [CalendarEventSnapshot]
    var eventError: Error?
    var delayNanoseconds: UInt64 = 0
    private(set) var calendarFetchCount = 0
    private(set) var eventFetchCount = 0
    private(set) var eventCalendarIDs: [String] = []
    private(set) var intervals: [DateInterval] = []
    private(set) var maximumConcurrentFetches = 0
    private var concurrentFetches = 0

    init(calendars: [CalendarDescriptor], events: [CalendarEventSnapshot]) {
        self.calendars = calendars
        self.events = events
    }

    func fetchCalendars(accessToken: String) async throws -> [CalendarDescriptor] {
        calendarFetchCount += 1
        concurrentFetches += 1
        maximumConcurrentFetches = max(maximumConcurrentFetches, concurrentFetches)
        defer { concurrentFetches -= 1 }
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        return calendars
    }

    func fetchEvents(
        calendar: CalendarDescriptor,
        in interval: DateInterval,
        accessToken: String
    ) async throws -> [CalendarEventSnapshot] {
        eventFetchCount += 1
        eventCalendarIDs.append(calendar.id)
        intervals.append(interval)
        if let eventError { throw eventError }
        return events.filter { $0.calendarIdentifier == calendar.id }
    }
}

@MainActor
private final class InMemoryCalendarCache: CalendarCacheRepository {
    var calendars: [CalendarDescriptor]
    var events: [CalendarEventSnapshot]
    var metadata: SyncMetadata?

    init(
        calendars: [CalendarDescriptor] = [],
        events: [CalendarEventSnapshot] = [],
        metadata: SyncMetadata? = nil
    ) {
        self.calendars = calendars
        self.events = events
        self.metadata = metadata
    }

    func fetchCalendars() throws -> [CalendarDescriptor] { calendars }
    func replaceCalendars(_ calendars: [CalendarDescriptor]) throws { self.calendars = calendars }
    func fetchEvents() throws -> [CalendarEventSnapshot] { events }
    func replaceEvents(_ events: [CalendarEventSnapshot]) throws { self.events = events }
    func fetchMetadata() throws -> SyncMetadata? { metadata }
    func saveMetadata(_ metadata: SyncMetadata) throws { self.metadata = metadata }
}

@MainActor
private final class RecordingCalendarReminderConsumer: CalendarReminderConsumer {
    private(set) var replacements: [[Reminder]] = []
    func replaceCalendarReminders(with reminders: [Reminder]) throws {
        replacements.append(reminders)
    }
}

@MainActor
private final class RecordingCalendarTimer: GoogleCalendarPeriodicRefreshScheduling {
    private(set) var intervals: [TimeInterval] = []
    private(set) var stopCount = 0
    private var action: (@MainActor () -> Void)?
    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        intervals.append(interval)
        self.action = action
    }
    func stop() {
        stopCount += 1
        action = nil
    }
    func fire() { action?() }
}

@MainActor
private final class InMemoryCalendarSettingsRepository: CalendarSettingsRepository {
    var settings: CalendarSettings?
    init(settings: CalendarSettings? = nil) { self.settings = settings }
    func fetchSettings() -> CalendarSettings? { settings }
    func save(_ settings: CalendarSettings) { self.settings = settings }
}

private func makeCalendar(
    id: String = "calendar",
    selected: Bool = true
) -> CalendarDescriptor {
    CalendarDescriptor(
        id: id,
        title: id,
        timeZoneIdentifier: "UTC",
        isSelectedInGoogleCalendar: selected,
        isPrimary: selected,
        defaultReminders: [.init(method: "popup", minutes: 10)]
    )
}

private func makeEvent(now: Date) -> CalendarEventSnapshot {
    CalendarEventSnapshot(
        eventIdentifier: "event",
        recurringEventIdentifier: nil,
        stableOccurrenceValue: "time:\(now.timeIntervalSince1970)",
        stableOccurrenceDate: now,
        calendarIdentifier: "calendar",
        calendarTitle: "calendar",
        calendarColorHex: nil,
        title: "event",
        location: nil,
        startDate: now.addingTimeInterval(600),
        endDate: now.addingTimeInterval(4_200),
        isAllDay: false,
        timeZoneIdentifier: "UTC",
        reminders: [.init(method: "popup", minutes: 10, duplicateOrdinal: 0)],
        sourceURL: nil
    )
}
