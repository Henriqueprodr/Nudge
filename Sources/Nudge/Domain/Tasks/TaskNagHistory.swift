import Foundation

/// Everything `TaskNagPolicy` needs to remember between launches.
struct TaskNagHistory: Codable, Equatable, Sendable {
    var observations: [String: TaskNagObservation] = [:]
    /// When each nag alert actually reached the screen; used for the daily limit and gap.
    var deliveredNagDates: [Date] = []

    static let empty = TaskNagHistory()

    var lastDeliveredNagDate: Date? {
        deliveredNagDates.max()
    }

    /// Adds first-seen records for new tasks and forgets tasks that are gone.
    mutating func reconcile(withIncompleteTaskIDs taskIDs: Set<String>, now: Date) {
        observations = observations.filter { taskIDs.contains($0.key) }
        for taskID in taskIDs where observations[taskID] == nil {
            observations[taskID] = TaskNagObservation(firstSeenAt: now)
        }
    }

    /// Keeps only the last few days of delivery dates.
    mutating func pruneDeliveries(before cutoff: Date) {
        deliveredNagDates.removeAll { $0 < cutoff }
    }

    mutating func recordDelivery(of taskIDs: [String], at date: Date) {
        deliveredNagDates.append(date)
        for taskID in taskIDs {
            var observation = observations[taskID] ?? TaskNagObservation(firstSeenAt: date)
            observation.lastNaggedAt = date
            observation.nagCount += 1
            observation.snoozedUntil = nil
            observations[taskID] = observation
        }
    }

    mutating func snooze(_ taskIDs: [String], until date: Date) {
        for taskID in taskIDs {
            observations[taskID]?.snoozedUntil = date
        }
    }

    mutating func silence(_ taskIDs: [String], until date: Date) {
        for taskID in taskIDs {
            observations[taskID]?.silencedUntil = date
        }
    }
}
