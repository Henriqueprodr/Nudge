import Foundation

struct GoogleTasksRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    let jitterFraction: Double

    static let defaultValue = GoogleTasksRetryPolicy(
        maximumAttempts: 3,
        baseDelay: 1,
        maximumDelay: 30,
        jitterFraction: 0.2
    )

    func delay(afterFailedAttempt failedAttempt: Int, randomUnit: Double) -> TimeInterval {
        let exponent = max(0, failedAttempt - 1)
        let exponentialDelay = min(
            maximumDelay,
            baseDelay * pow(2, Double(exponent))
        )
        let normalizedRandom = min(max(randomUnit, 0), 1)
        let jitterMultiplier = 1 + jitterFraction * ((2 * normalizedRandom) - 1)
        return max(0, min(maximumDelay, exponentialDelay * jitterMultiplier))
    }
}
