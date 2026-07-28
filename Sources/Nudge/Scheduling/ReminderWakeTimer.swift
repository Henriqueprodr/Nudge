import Foundation

@MainActor
final class ReminderWakeTimer: NSObject {
    private var timer: Timer?
    private var action: (() -> Void)?

    private(set) var scheduledDate: Date?

    func schedule(at date: Date, action: @escaping () -> Void) {
        cancel()
        scheduledDate = date
        self.action = action

        let timer = Timer(
            fireAt: date,
            interval: 0,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: false
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        action = nil
        scheduledDate = nil
    }

    @objc
    private func timerDidFire() {
        let action = action
        cancel()
        action?()
    }
}
