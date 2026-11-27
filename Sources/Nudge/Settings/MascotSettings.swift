import Foundation

/// How the bird behaves.
struct MascotSettings: Codable, Equatable, Sendable {
    /// How unfiltered the bird's commentary is.
    enum Spice: String, Codable, CaseIterable, Identifiable, Sendable {
        case mild
        case spicy
        case unhinged

        var id: Self { self }

        var label: String {
            switch self {
            case .mild: return "Mild"
            case .spicy: return "Spicy"
            case .unhinged: return "Unhinged"
            }
        }

        var summary: String {
            switch self {
            case .mild: return "Polite encouragement."
            case .spicy: return "Light roasting."
            case .unhinged: return "Foul-mouthed, merciless, zero filter. Not for screen sharing."
            }
        }
    }

    var isEnabled: Bool
    /// The bird delivers calendar, task, and sign-in alerts.
    var deliversAlerts: Bool
    /// The bird also drops by between alerts.
    var makesIdleVisits: Bool
    /// Average minutes between idle visits (each visit is randomized ±⅓).
    var idleVisitIntervalMinutes: Int
    var spice: Spice
    /// The bird whistles on idle visits.
    var whistles: Bool
    /// No visits or alert deliveries before this date.
    var doNotDisturbUntil: Date?

    static let defaultValue = MascotSettings(
        isEnabled: true,
        deliversAlerts: true,
        makesIdleVisits: true,
        idleVisitIntervalMinutes: 90,
        spice: .spicy,
        whistles: true,
        doNotDisturbUntil: nil
    )

    static let idleVisitIntervalRange = 15...240

    var validated: MascotSettings {
        var copy = self
        copy.idleVisitIntervalMinutes = min(
            max(idleVisitIntervalMinutes, Self.idleVisitIntervalRange.lowerBound),
            Self.idleVisitIntervalRange.upperBound
        )
        return copy
    }

    func isQuiet(at date: Date) -> Bool {
        guard isEnabled else { return true }
        if let doNotDisturbUntil, doNotDisturbUntil > date { return true }
        return false
    }
}
