import Foundation

enum SingleApplicationInstancePolicy {
    static func primaryProcessIdentifier(
        currentProcessIdentifier: pid_t,
        runningProcessIdentifiers: [pid_t]
    ) -> pid_t {
        (runningProcessIdentifiers + [currentProcessIdentifier]).min()
            ?? currentProcessIdentifier
    }

    static func shouldContinueLaunching(
        currentProcessIdentifier: pid_t,
        runningProcessIdentifiers: [pid_t]
    ) -> Bool {
        currentProcessIdentifier == primaryProcessIdentifier(
            currentProcessIdentifier: currentProcessIdentifier,
            runningProcessIdentifiers: runningProcessIdentifiers
        )
    }
}
