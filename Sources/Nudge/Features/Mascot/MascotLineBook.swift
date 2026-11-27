import Foundation

/// The bird's lines, grouped by category and spice level.
///
/// Lines ship in `MascotLines.json`. A file with the same shape at
/// `~/Library/Application Support/Nudge/MascotLines.json` adds to them, so you can teach the
/// bird new material without rebuilding. Placeholders: `{task}`, `{event}`, `{days}`, `{count}`.
struct MascotLineBook: Sendable {
    typealias Lines = [String: [String: [String]]]

    private let lines: Lines

    init(lines: Lines) {
        self.lines = lines
    }

    static let userFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Nudge/MascotLines.json")
    }()

    /// Bundled lines merged with the optional user file.
    static func load(bundle: Bundle = .main, userFileURL: URL? = MascotLineBook.userFileURL) -> MascotLineBook {
        var merged: Lines = [:]
        let sources = [bundle.url(forResource: "MascotLines", withExtension: "json"), userFileURL]
        for url in sources.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(Lines.self, from: data) else { continue }
            for (category, levels) in decoded {
                for (level, entries) in levels {
                    merged[category, default: [:]][level, default: []].append(contentsOf: entries)
                }
            }
        }
        if merged.isEmpty {
            merged = [MascotLineCategory.idle.rawValue: [MascotSettings.Spice.mild.rawValue: ["Hi."]]]
        }
        return MascotLineBook(lines: merged)
    }

    /// Lines available at a spice level. Spicier levels include the milder ones, but the
    /// selection is weighted toward the chosen level.
    func candidates(for category: MascotLineCategory, spice: MascotSettings.Spice) -> [String] {
        let levels = lines[category.rawValue] ?? [:]
        let mild = levels[MascotSettings.Spice.mild.rawValue] ?? []
        let spicy = levels[MascotSettings.Spice.spicy.rawValue] ?? []
        let unhinged = levels[MascotSettings.Spice.unhinged.rawValue] ?? []
        switch spice {
        case .mild:
            return mild
        case .spicy:
            return mild + spicy + spicy
        case .unhinged:
            return mild + spicy + unhinged + unhinged + unhinged
        }
    }

    func line(
        for category: MascotLineCategory,
        spice: MascotSettings.Spice,
        substitutions: [String: String] = [:],
        avoiding recent: Set<String> = [],
        randomUnit: () -> Double = { Double.random(in: 0..<1) }
    ) -> String {
        var pool = candidates(for: category, spice: spice)
        if pool.isEmpty {
            pool = candidates(for: .idle, spice: spice)
        }
        let fresh = pool.filter { !recent.contains($0) }
        let choices = fresh.isEmpty ? pool : fresh
        guard !choices.isEmpty else { return "" }
        let index = min(Int(randomUnit() * Double(choices.count)), choices.count - 1)
        return Self.fill(choices[index], with: substitutions)
    }

    static func fill(_ template: String, with substitutions: [String: String]) -> String {
        substitutions.reduce(template) { text, pair in
            text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }

    /// Trims a title the bird quotes to about `limit` characters at a word boundary, adding "…".
    /// The alert itself still shows the full title.
    static func shortened(_ title: String, limit: Int = 48) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let prefix = String(trimmed.prefix(limit))
        let endsOnWordBoundary = trimmed[trimmed.index(trimmed.startIndex, offsetBy: limit)]
            .isWhitespace
        let cut = endsOnWordBoundary
            ? prefix
            : prefix.lastIndex(where: { $0.isWhitespace }).map { String(prefix[..<$0]) } ?? prefix
        let base = cut.count >= limit / 2 ? cut : prefix
        return base.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) + "…"
    }
}
