import Foundation

@MainActor
protocol GoogleTasksPeriodicRefreshScheduling: AnyObject {
    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class GoogleTasksPeriodicRefreshTimer: GoogleTasksPeriodicRefreshScheduling {
    private var refreshTask: Task<Void, Never>?

    func start(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        stop()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                action()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
