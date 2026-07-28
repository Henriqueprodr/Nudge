import Foundation

@MainActor
protocol GoogleCalendarPeriodicRefreshScheduling: AnyObject {
    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class GoogleCalendarPeriodicRefreshTimer: GoogleCalendarPeriodicRefreshScheduling {
    private var refreshTask: Task<Void, Never>?

    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        stop()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(0, interval) * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                action()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
