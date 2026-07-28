import Foundation

struct GoogleCalendarRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    let jitterFraction: Double

    static let defaultValue = GoogleCalendarRetryPolicy(
        maximumAttempts: 3,
        baseDelay: 1,
        maximumDelay: 30,
        jitterFraction: 0.2
    )

    func delay(afterFailedAttempt failedAttempt: Int, randomUnit: Double) -> TimeInterval {
        let exponent = max(0, failedAttempt - 1)
        let delay = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let normalized = min(max(randomUnit, 0), 1)
        return max(0, min(maximumDelay, delay * (1 + jitterFraction * ((2 * normalized) - 1))))
    }
}
