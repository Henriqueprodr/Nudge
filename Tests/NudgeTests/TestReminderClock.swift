import Foundation
@testable import Nudge

final class TestReminderClock: ReminderClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
