import AppKit
import Foundation

@MainActor
protocol ApplicationLifecycleEventProviding: AnyObject {
    func start(handler: @escaping @MainActor (ApplicationLifecycleCoordinator.Event) -> Void)
    func stop()
}

@MainActor
protocol LifecycleWindowRecovering: AnyObject {
    func prepareForSleep()
    func setSessionActive(_ isActive: Bool)
    func recoverAfterLifecycleChange()
}

@MainActor
protocol LifecycleCalendarRecovering: AnyObject {
    func recoverScheduleFromCache()
    func requestRefresh(_ trigger: GoogleCalendarRefreshTrigger)
}

@MainActor
protocol LifecycleTasksRefreshing: AnyObject {
    func requestRefresh(_ trigger: GoogleTasksRefreshTrigger)
}

@MainActor
final class ApplicationLifecycleCoordinator: NSObject {
    enum Event: Sendable {
        case willSleep
        case didWake
        case sessionBecameActive
        case sessionResignedActive
        case significantTimeChange
        case screenParametersChanged
        case activeSpaceChanged
    }

    private let windowCoordinator: any LifecycleWindowRecovering
    private let calendarCoordinator: any LifecycleCalendarRecovering
    private let tasksCoordinator: any LifecycleTasksRefreshing
    private let eventProvider: any ApplicationLifecycleEventProviding
    private var recoveryTask: Task<Void, Never>?
    private var wakeRefreshPending = false
    private var wakeRefreshHandledForCycle = false

    init(
        windowCoordinator: any LifecycleWindowRecovering,
        calendarCoordinator: any LifecycleCalendarRecovering,
        tasksCoordinator: any LifecycleTasksRefreshing,
        eventProvider: any ApplicationLifecycleEventProviding = SystemApplicationLifecycleEventProvider()
    ) {
        self.windowCoordinator = windowCoordinator
        self.calendarCoordinator = calendarCoordinator
        self.tasksCoordinator = tasksCoordinator
        self.eventProvider = eventProvider
    }

    func start() {
        eventProvider.start { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        eventProvider.stop()
    }

    func handle(_ event: Event) {
        switch event {
        case .willSleep:
            wakeRefreshHandledForCycle = false
            wakeRefreshPending = false
            windowCoordinator.prepareForSleep()
        case .didWake:
            if !wakeRefreshHandledForCycle {
                wakeRefreshPending = true
                wakeRefreshHandledForCycle = true
            }
            scheduleRecovery()
        case .sessionBecameActive:
            windowCoordinator.setSessionActive(true)
            scheduleRecovery()
        case .sessionResignedActive:
            windowCoordinator.setSessionActive(false)
        case .significantTimeChange, .screenParametersChanged, .activeSpaceChanged:
            scheduleRecovery()
        }
    }

    func flushPendingRecovery() async {
        await recoveryTask?.value
    }

    private func scheduleRecovery() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let shouldRefresh = wakeRefreshPending
            wakeRefreshPending = false
            windowCoordinator.recoverAfterLifecycleChange()
            calendarCoordinator.recoverScheduleFromCache()
            if shouldRefresh {
                calendarCoordinator.requestRefresh(.wake)
                tasksCoordinator.requestRefresh(.wake)
            }
            recoveryTask = nil
        }
    }
}

extension WindowPresentationCoordinator: LifecycleWindowRecovering {}
extension CalendarScheduleCoordinator: LifecycleCalendarRecovering {}
extension GoogleTasksSyncCoordinator: LifecycleTasksRefreshing {}

@MainActor
final class SystemApplicationLifecycleEventProvider: ApplicationLifecycleEventProviding {
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var applicationObserverTokens: [NSObjectProtocol] = []

    func start(handler: @escaping @MainActor (ApplicationLifecycleCoordinator.Event) -> Void) {
        guard workspaceObserverTokens.isEmpty, applicationObserverTokens.isEmpty else {
            return
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens = [
            observe(workspaceCenter, .willSleep, handler: handler),
            observe(workspaceCenter, .didWake, handler: handler),
            observe(workspaceCenter, .sessionBecameActive, handler: handler),
            observe(workspaceCenter, .sessionResignedActive, handler: handler),
            observe(workspaceCenter, .activeSpaceChanged, handler: handler),
        ]
        let center = NotificationCenter.default
        applicationObserverTokens = [
            observe(center, .significantTimeChange, name: .NSSystemClockDidChange, handler: handler),
            observe(center, .significantTimeChange, name: .NSSystemTimeZoneDidChange, handler: handler),
            observe(
                center,
                .screenParametersChanged,
                name: NSApplication.didChangeScreenParametersNotification,
                handler: handler
            ),
        ]
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.forEach(workspaceCenter.removeObserver)
        workspaceObserverTokens.removeAll()
        let center = NotificationCenter.default
        applicationObserverTokens.forEach(center.removeObserver)
        applicationObserverTokens.removeAll()
    }

    private enum WorkspaceEvent {
        case willSleep
        case didWake
        case sessionBecameActive
        case sessionResignedActive
        case activeSpaceChanged

        var name: Notification.Name {
            switch self {
            case .willSleep:
                return NSWorkspace.willSleepNotification
            case .didWake:
                return NSWorkspace.didWakeNotification
            case .sessionBecameActive:
                return NSWorkspace.sessionDidBecomeActiveNotification
            case .sessionResignedActive:
                return NSWorkspace.sessionDidResignActiveNotification
            case .activeSpaceChanged:
                return NSWorkspace.activeSpaceDidChangeNotification
            }
        }

        var lifecycleEvent: ApplicationLifecycleCoordinator.Event {
            switch self {
            case .willSleep:
                return .willSleep
            case .didWake:
                return .didWake
            case .sessionBecameActive:
                return .sessionBecameActive
            case .sessionResignedActive:
                return .sessionResignedActive
            case .activeSpaceChanged:
                return .activeSpaceChanged
            }
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ event: WorkspaceEvent,
        handler: @escaping @MainActor (ApplicationLifecycleCoordinator.Event) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: event.name, object: nil, queue: .main) { _ in
            Task { @MainActor in handler(event.lifecycleEvent) }
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ event: ApplicationLifecycleCoordinator.Event,
        name: Notification.Name,
        handler: @escaping @MainActor (ApplicationLifecycleCoordinator.Event) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in handler(event) }
        }
    }
}
