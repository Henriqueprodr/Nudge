import Foundation

enum ReminderSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case hero
    case bottle
    case morse
    case sosumi

    static let defaultValue = ReminderSound.hero

    var id: Self { self }

    var label: String {
        switch self {
        case .off:
            return "Off"
        case .hero:
            return "Hero"
        case .bottle:
            return "Bottle"
        case .morse:
            return "Morse"
        case .sosumi:
            return "Sosumi"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .off:
            return nil
        case .hero:
            return "Hero"
        case .bottle:
            return "Bottle"
        case .morse:
            return "Morse"
        case .sosumi:
            return "Sosumi"
        }
    }

    var isEnabled: Bool {
        self != .off
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)
        switch storedValue {
        case Self.off.rawValue:
            self = .off
        case Self.hero.rawValue:
            self = .hero
        case Self.bottle.rawValue:
            self = .bottle
        case Self.morse.rawValue:
            self = .morse
        case Self.sosumi.rawValue:
            self = .sosumi
        case "ping", "pop", "glass", "tink", "purr":
            self = .hero
        default:
            self = .defaultValue
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
