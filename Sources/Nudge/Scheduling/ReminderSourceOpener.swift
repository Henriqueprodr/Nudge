import Foundation

@MainActor
protocol ReminderSourceOpening: AnyObject {
    func openSource(for reminder: Reminder) -> Bool
}

@MainActor
final class ReminderSourceOpener: ReminderSourceOpening {
    private let browserOpener: any SystemBrowserOpening

    init(
        browserOpener: any SystemBrowserOpening = SystemBrowserOpener()
    ) {
        self.browserOpener = browserOpener
    }

    func openSource(for reminder: Reminder) -> Bool {
        guard let sourceURL = reminder.sourceURL else {
            return false
        }
        if reminder.occurrenceID.sourceKind == .calendar,
           GoogleCalendarLinkValidator.validatedURL(from: sourceURL.absoluteString) == nil {
            return false
        }
        return browserOpener.open(sourceURL)
    }
}
