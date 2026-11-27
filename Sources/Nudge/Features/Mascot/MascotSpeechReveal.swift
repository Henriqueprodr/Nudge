import Foundation
import SwiftUI

/// Times the word-by-word fade-in of a bird line.
///
/// Only each word's opacity changes over time. The characters and font never do, so line breaks
/// and the bubble's size are identical on every frame and the bubble never grows while it fills.
struct MascotSpeechReveal: Equatable, Sendable {
    static let fadeDuration: TimeInterval = 0.18
    static let charactersPerSecond: Double = 30
    static let durationRange: ClosedRange<TimeInterval> = 0.8...2.6

    struct Word: Equatable, Sendable {
        /// Offset of the word's first character within the text.
        var range: Range<Int>
        /// Seconds after the reveal starts when this word begins to fade in.
        var start: TimeInterval
    }

    let text: String
    /// Time until the last word begins to fade in.
    let duration: TimeInterval
    let words: [Word]

    init(text: String) {
        self.text = text
        let characters = Array(text)
        let total = max(characters.count, 1)
        let duration = min(
            max(Double(total) / Self.charactersPerSecond, Self.durationRange.lowerBound),
            Self.durationRange.upperBound
        )
        var words: [Word] = []
        var index = 0
        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
                continue
            }
            let start = index
            while index < characters.count, !characters[index].isWhitespace {
                index += 1
            }
            words.append(Word(range: start..<index, start: 0))
        }
        // The first word starts at once and the last one at `duration`, spaced by characters.
        let lastStart = words.last.map { Double($0.range.lowerBound) } ?? 0
        for position in words.indices {
            let fraction = lastStart > 0 ? Double(words[position].range.lowerBound) / lastStart : 0
            words[position].start = fraction * duration
        }
        self.duration = duration
        self.words = words
    }

    /// When every word is fully visible.
    var totalDuration: TimeInterval {
        duration + Self.fadeDuration
    }

    func opacity(ofWord position: Int, elapsed: TimeInterval) -> Double {
        let progress = (elapsed - words[position].start) / Self.fadeDuration
        return min(max(progress, 0), 1)
    }

    func isComplete(elapsed: TimeInterval) -> Bool {
        elapsed >= totalDuration
    }

    /// The full text, with each word tinted `color` at its current opacity.
    func attributedText(elapsed: TimeInterval, color: Color) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color.opacity(0)
        let characterIndices = Array(result.characters.indices)
        for position in words.indices {
            let range = words[position].range
            let lower = characterIndices[range.lowerBound]
            let upper = range.upperBound < characterIndices.count
                ? characterIndices[range.upperBound]
                : result.endIndex
            result[lower..<upper].foregroundColor = color.opacity(
                opacity(ofWord: position, elapsed: elapsed)
            )
        }
        return result
    }

    /// Redraw times for a reveal that starts at `start`, ending once the line is fully shown.
    func frameDates(from start: Date, interval: TimeInterval = 1.0 / 30) -> [Date] {
        let count = Int((totalDuration / interval).rounded(.up))
        return (0...count).map { start.addingTimeInterval(Double($0) * interval) }
    }
}
