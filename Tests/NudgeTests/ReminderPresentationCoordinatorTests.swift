import Foundation
import XCTest
@testable import Nudge

final class ReminderPresentationCoordinatorTests: XCTestCase {
    @MainActor
    func testVisibleReminderPlaysConfiguredSoundOnlyOnceAcrossDuplicateProcessing() async throws {
        let now = Date(timeIntervalSince1970: 70_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = testSoundWindowController(isAvailable: true)
        let soundPlayer = TestReminderSoundPlayer()
        let firstPlayback = expectation(description: "Visible reminder played its sound")
        soundPlayer.onPlay = { firstPlayback.fulfill() }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: windowController,
            soundPlayer: soundPlayer,
            now: { now }
        )
        coordinator.reminderSound = .sosumi
        let reminder = makeDueReminder(identifier: "one-sound", date: now)

        try coordinator.process([reminder])
        await fulfillment(of: [firstPlayback], timeout: 1)
        try coordinator.process([reminder])
        await Task.yield()

        XCTAssertEqual(soundPlayer.playedSounds, [.sosumi])
        windowController.dismiss()
    }

    @MainActor
    func testOffAndUnavailableOverlayDoNotPlayReminderSound() async throws {
        let now = Date(timeIntervalSince1970: 71_000)
        let offContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let offWindowController = testSoundWindowController(isAvailable: true)
        let offSoundPlayer = TestReminderSoundPlayer()
        let offCoordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: offContainer.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: offWindowController,
            soundPlayer: offSoundPlayer,
            now: { now }
        )
        offCoordinator.reminderSound = .off

        try offCoordinator.process([makeDueReminder(identifier: "sound-off", date: now)])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(offSoundPlayer.playedSounds.isEmpty)
        offWindowController.dismiss()

        let unavailableContainer = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let unavailableWindowController = testSoundWindowController(isAvailable: false)
        let unavailableSoundPlayer = TestReminderSoundPlayer()
        let unavailableCoordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: unavailableContainer.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: unavailableWindowController,
            soundPlayer: unavailableSoundPlayer,
            now: { now }
        )

        try unavailableCoordinator.process([
            makeDueReminder(identifier: "overlay-unavailable", date: now)
        ])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(unavailableSoundPlayer.playedSounds.isEmpty)
        XCTAssertFalse(unavailableWindowController.isVisible)
    }

    @MainActor
    func testSnoozedReminderPlaysAgainWhenItReturns() async throws {
        let now = Date(timeIntervalSince1970: 72_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = testSoundWindowController(isAvailable: true)
        let soundPlayer = TestReminderSoundPlayer()
        let firstPlayback = expectation(description: "Initial sound")
        let secondPlayback = expectation(description: "Sound after snooze")
        soundPlayer.onPlay = {
            if soundPlayer.playedSounds.count == 1 {
                firstPlayback.fulfill()
            } else if soundPlayer.playedSounds.count == 2 {
                secondPlayback.fulfill()
            }
        }
        let wakeTimer = ReminderWakeTimer()
        defer {
            wakeTimer.cancel()
            windowController.dismiss()
        }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: clock
            ),
            windowController: windowController,
            wakeTimer: wakeTimer,
            soundPlayer: soundPlayer,
            now: { clock.now }
        )
        let reminder = makeDueReminder(identifier: "snooze-sound", date: now)

        try coordinator.process([reminder])
        await fulfillment(of: [firstPlayback], timeout: 1)
        coordinator.snoozeCurrentReminder(for: 10 * 60)
        clock.now = now.addingTimeInterval(10 * 60)
        coordinator.recoverAfterLifecycleChange()
        await fulfillment(of: [secondPlayback], timeout: 1)

        XCTAssertEqual(soundPlayer.playedSounds, [.hero, .hero])
    }

    @MainActor
    func testQueuedRemindersEachPlayWhenTheyBecomeVisible() async throws {
        let now = Date(timeIntervalSince1970: 73_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = testSoundWindowController(isAvailable: true)
        let soundPlayer = TestReminderSoundPlayer()
        let firstPlayback = expectation(description: "First queued reminder sound")
        let secondPlayback = expectation(description: "Second queued reminder sound")
        soundPlayer.onPlay = {
            if soundPlayer.playedSounds.count == 1 {
                firstPlayback.fulfill()
            } else if soundPlayer.playedSounds.count == 2 {
                secondPlayback.fulfill()
            }
        }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: windowController,
            soundPlayer: soundPlayer,
            now: { now }
        )

        try coordinator.process([
            makeDueReminder(identifier: "queue-one", date: now),
            makeDueReminder(identifier: "queue-two", date: now)
        ])
        await fulfillment(of: [firstPlayback], timeout: 1)
        coordinator.dismissCurrentReminder()
        await fulfillment(of: [secondPlayback], timeout: 1)

        XCTAssertEqual(soundPlayer.playedSounds, [.hero, .hero])
        windowController.dismiss()
    }

    @MainActor
    func testFutureReminderArmsOneShotDeadlineWithoutShowingOverlayEarly() throws {
        let now = Date()
        let futureDate = now.addingTimeInterval(10 * 60)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let wakeTimer = ReminderWakeTimer()
        defer {
            wakeTimer.cancel()
        }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: clock
            ),
            windowController: windowController,
            wakeTimer: wakeTimer
        )
        let reminder = Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .local,
                sourceIdentifier: "future-presentation",
                occurrenceDate: futureDate,
                revision: nil
            ),
            title: "Future reminder",
            detail: nil,
            triggerDate: futureDate,
            expirationDate: nil,
            presentationMode: .overlay
        )

        try coordinator.process([reminder])

        XCTAssertEqual(coordinator.nextScheduledPresentationDate, futureDate)
        XCTAssertFalse(windowController.isVisible)
    }

    @MainActor
    func testSnoozeActionPersistsAndArmsOneShotReturn() throws {
        let now = Date(timeIntervalSince1970: 80_000)
        let clock = TestReminderClock(now: now)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let wakeTimer = ReminderWakeTimer()
        defer { wakeTimer.cancel() }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: clock
            ),
            windowController: windowController,
            wakeTimer: wakeTimer,
            now: { now }
        )
        let reminder = makeDueReminder(identifier: "snooze-action", date: now)

        try coordinator.process([reminder])
        coordinator.snoozeCurrentReminder(for: 10 * 60)

        let record = try container.reminderDeliveryRepository.deliveryRecord(
            for: reminder.occurrenceID
        )
        XCTAssertEqual(record?.state, .snoozed)
        XCTAssertEqual(record?.snoozedUntil, now.addingTimeInterval(10 * 60))
        XCTAssertEqual(
            coordinator.nextScheduledPresentationDate,
            now.addingTimeInterval(10 * 60)
        )
        XCTAssertFalse(windowController.isVisible)
    }

    @MainActor
    func testOpenSourceMarksReminderActedOnlyAfterSupportedURLIsOpened() throws {
        let now = Date(timeIntervalSince1970: 90_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let opener = TestReminderSourceOpener()
        let reminder = makeDueReminder(identifier: "open-source", date: now)
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: windowController,
            sourceOpener: opener,
            now: { now }
        )

        try coordinator.process([reminder])
        coordinator.openCurrentReminderSource()

        XCTAssertEqual(opener.openedReminders, [reminder])
        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(
                for: reminder.occurrenceID
            )?.state,
            .acted
        )
        XCTAssertFalse(windowController.isVisible)
    }

    @MainActor
    func testTaskAndCalendarReplacementNeverClobberEachOther() throws {
        let now = Date(timeIntervalSince1970: 95_000)
        let future = now.addingTimeInterval(30 * 60)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = ReminderOverlayWindowController(store: ReminderOverlayStore())
        let wakeTimer = ReminderWakeTimer()
        defer { wakeTimer.cancel() }
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: windowController,
            wakeTimer: wakeTimer,
            now: { now }
        )
        func reminder(_ kind: ReminderOccurrenceID.SourceKind, at date: Date) -> Reminder {
            Reminder(
                occurrenceID: ReminderOccurrenceID(
                    sourceKind: kind, sourceIdentifier: "\(kind)", occurrenceDate: date, revision: nil
                ),
                title: "\(kind)",
                detail: nil,
                triggerDate: date,
                expirationDate: nil,
                presentationMode: .overlay
            )
        }

        try coordinator.replaceCalendarReminders(with: [reminder(.calendar, at: future)])
        try coordinator.replaceTaskReminders(with: [reminder(.task, at: future.addingTimeInterval(60))])
        XCTAssertEqual(coordinator.nextScheduledPresentationDate, future)

        // Clearing task nags leaves the calendar reminder armed.
        try coordinator.replaceTaskReminders(with: [])
        XCTAssertEqual(coordinator.nextScheduledPresentationDate, future)

        // Clearing calendar reminders leaves a task nag armed, and kinds never cross over.
        try coordinator.replaceTaskReminders(with: [reminder(.task, at: future.addingTimeInterval(60))])
        try coordinator.replaceCalendarReminders(with: [reminder(.task, at: future)])
        XCTAssertEqual(coordinator.nextScheduledPresentationDate, future.addingTimeInterval(60))
    }

    @MainActor
    func testReminderActionRunsHandlerThenMarksActed() async throws {
        let now = Date(timeIntervalSince1970: 97_000)
        let container = try LocalRepositoryContainer(isStoredInMemoryOnly: true)
        let windowController = testSoundWindowController(isAvailable: true)
        let coordinator = ReminderPresentationCoordinator(
            scheduler: ReminderScheduler(
                repository: container.reminderDeliveryRepository,
                clock: TestReminderClock(now: now)
            ),
            windowController: windowController,
            soundPlayer: TestReminderSoundPlayer(),
            now: { now }
        )
        var handled: [ReminderAction] = []
        let finished = expectation(description: "action handled")
        coordinator.actionHandler = { action, _ in
            handled.append(action)
            finished.fulfill()
            return true
        }
        var reminder = makeDueReminder(identifier: "action", date: now)
        reminder.actions = [.notToday]

        try coordinator.process([reminder])
        coordinator.performCurrentReminderAction(.completeTask)
        XCTAssertTrue(handled.isEmpty, "Actions the reminder does not offer are ignored")
        coordinator.performCurrentReminderAction(.notToday)
        await fulfillment(of: [finished], timeout: 1)
        await Task.yield()

        XCTAssertEqual(handled, [.notToday])
        XCTAssertEqual(
            try container.reminderDeliveryRepository.deliveryRecord(
                for: reminder.occurrenceID
            )?.state,
            .acted
        )
        XCTAssertFalse(windowController.isVisible)
    }

    private func makeDueReminder(identifier: String, date: Date) -> Reminder {
        Reminder(
            occurrenceID: ReminderOccurrenceID(
                sourceKind: .calendar,
                sourceIdentifier: identifier,
                occurrenceDate: date,
                revision: nil
            ),
            title: "Due reminder",
            detail: nil,
            triggerDate: date,
            expirationDate: date.addingTimeInterval(15 * 60),
            presentationMode: .overlay,
            sourceURL: URL(string: "https://calendar.google.com/calendar/event?eid=opaque")
        )
    }
}

@MainActor
private final class TestReminderSoundPlayer: ReminderSoundPlaying {
    private(set) var playedSounds: [ReminderSound] = []
    var onPlay: (() -> Void)?

    func play(_ sound: ReminderSound) {
        playedSounds.append(sound)
        onPlay?()
    }

    func stop() {}
}

@MainActor
private func testSoundWindowController(isAvailable: Bool) -> ReminderOverlayWindowController {
    let controller = ReminderOverlayWindowController(
        store: ReminderOverlayStore(),
        presentationAvailability: { _ in isAvailable },
        reduceMotion: { true },
        sleeper: { _ in try await Task.sleep(nanoseconds: UInt64.max) },
        alphaAnimator: { window, endAlpha, _ in
            window.alphaValue = endAlpha
        }
    )
    controller.persistsUntilAction = true
    return controller
}

@MainActor
private final class TestReminderSourceOpener: ReminderSourceOpening {
    private(set) var openedReminders: [Reminder] = []

    func openSource(for reminder: Reminder) -> Bool {
        openedReminders.append(reminder)
        return true
    }
}
