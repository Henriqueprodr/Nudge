import Foundation

struct TaskPriorityPalette: Codable, Equatable, Sendable {
    static let defaultValue = TaskPriorityPalette(
        highColorHex: "#FF3B30",
        mediumColorHex: "#FF9500",
        lowColorHex: "#FFD60A"
    )

    var highColorHex: String
    var mediumColorHex: String
    var lowColorHex: String

    private enum CodingKeys: String, CodingKey {
        case highColorHex
        case mediumColorHex
        case lowColorHex
    }

    init(highColorHex: String, mediumColorHex: String, lowColorHex: String) {
        self.highColorHex = Self.validatedHex(highColorHex, fallback: "#FF3B30")
        self.mediumColorHex = Self.validatedHex(mediumColorHex, fallback: "#FF9500")
        self.lowColorHex = Self.validatedHex(lowColorHex, fallback: "#FFD60A")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            highColorHex: try container.decode(String.self, forKey: .highColorHex),
            mediumColorHex: try container.decode(String.self, forKey: .mediumColorHex),
            lowColorHex: try container.decode(String.self, forKey: .lowColorHex)
        )
    }

    func colorHex(for priority: TaskPriority) -> String? {
        switch priority {
        case .high:
            return highColorHex
        case .medium:
            return mediumColorHex
        case .low:
            return lowColorHex
        case .none:
            return nil
        }
    }

    func updating(_ priority: TaskPriority, colorHex: String) -> TaskPriorityPalette {
        switch priority {
        case .high:
            return TaskPriorityPalette(
                highColorHex: colorHex,
                mediumColorHex: mediumColorHex,
                lowColorHex: lowColorHex
            )
        case .medium:
            return TaskPriorityPalette(
                highColorHex: highColorHex,
                mediumColorHex: colorHex,
                lowColorHex: lowColorHex
            )
        case .low:
            return TaskPriorityPalette(
                highColorHex: highColorHex,
                mediumColorHex: mediumColorHex,
                lowColorHex: colorHex
            )
        case .none:
            return self
        }
    }

    static func validatedHex(_ value: String, fallback: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6, UInt64(normalized, radix: 16) != nil else {
            return fallback
        }
        return "#\(normalized)"
    }
}
