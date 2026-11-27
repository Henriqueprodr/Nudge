/// What the bird is talking about.
enum MascotLineCategory: String, Codable, CaseIterable, Sendable {
    case idle
    case poked
    case calendarSoon
    case taskDueToday
    case taskOverdue
    case taskAncient
    case taskLingering
    case taskDone
    case signedOut

    /// The category for a reminder strip's tone.
    init(tone: ReminderStripPresentation.Tone) {
        switch tone {
        case .calendar, .generic:
            self = .calendarSoon
        case .actionNeeded:
            self = .signedOut
        case let .task(urgency):
            switch urgency {
            case .dueToday: self = .taskDueToday
            case .overdue: self = .taskOverdue
            case .ancient: self = .taskAncient
            case .lingering: self = .taskLingering
            }
        }
    }
}
