import Foundation

protocol ReminderClock {
    var now: Date { get }
}

struct SystemReminderClock: ReminderClock {
    var now: Date {
        Date()
    }
}
