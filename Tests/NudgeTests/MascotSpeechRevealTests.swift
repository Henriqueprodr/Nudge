import AppKit
import SwiftUI
import XCTest
@testable import Nudge

/// The bird's words fade in one by one inside a bubble that is sized for the whole line.
final class MascotSpeechRevealTests: XCTestCase {
    private static let longLine =
        "FYI: yo shit ain't done ma boy... \"Finish the quarterly report draft\" is 3 days late. "
        + "Get it done ASAP."

    func testRevealKeepsEveryCharacterAndOnlyChangesOpacity() {
        let text = "  Two  spaces,\ta tab and an emoji 🐦 stay put.  "
        let reveal = MascotSpeechReveal(text: text)
        for elapsed in [0, 0.4, 1, 5] as [TimeInterval] {
            let attributed = reveal.attributedText(elapsed: elapsed, color: .black)
            XCTAssertEqual(String(attributed.characters), text)
        }
        XCTAssertEqual(reveal.words.count, 10)
    }

    func testOnlyTheFirstWordHasStartedAtTheBeginning() {
        let reveal = MascotSpeechReveal(text: Self.longLine)
        XCTAssertEqual(reveal.words.first?.start, 0)
        XCTAssertTrue(reveal.words.dropFirst().allSatisfy { $0.start > 0 })
        XCTAssertEqual(reveal.words.last?.start ?? 0, reveal.duration, accuracy: 0.0001)
        XCTAssertFalse(reveal.isComplete(elapsed: reveal.duration))
    }

    func testEveryWordIsFullyVisibleOnceTheRevealEnds() {
        let reveal = MascotSpeechReveal(text: Self.longLine)
        for position in reveal.words.indices {
            XCTAssertEqual(reveal.opacity(ofWord: position, elapsed: reveal.totalDuration), 1)
        }
        XCTAssertTrue(reveal.isComplete(elapsed: reveal.totalDuration))
    }

    func testOpacityNeverDecreases() {
        let reveal = MascotSpeechReveal(text: Self.longLine)
        for position in reveal.words.indices {
            var previous = 0.0
            for step in 0...100 {
                let value = reveal.opacity(
                    ofWord: position, elapsed: reveal.totalDuration * Double(step) / 100
                )
                XCTAssertGreaterThanOrEqual(value, previous)
                previous = value
            }
        }
    }

    func testDurationStaysWithinBoundsAndFrameDatesStopAtTheEnd() {
        let short = MascotSpeechReveal(text: "Hi!")
        let long = MascotSpeechReveal(text: String(repeating: "pecking ", count: 60))
        XCTAssertEqual(short.duration, MascotSpeechReveal.durationRange.lowerBound)
        XCTAssertEqual(long.duration, MascotSpeechReveal.durationRange.upperBound)

        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let dates = long.frameDates(from: start)
        XCTAssertEqual(dates.first, start)
        let last = dates.last?.timeIntervalSince(start) ?? 0
        XCTAssertGreaterThanOrEqual(last, long.totalDuration)
        XCTAssertLessThan(last, long.totalDuration + 0.05)
    }

    // MARK: Bubble sizing (regression: a fixed-size bubble was one line tall for any text)

    @MainActor
    func testLongLineWrapsInsideABubbleTallEnoughForIt() {
        let verticalPadding: CGFloat = 10 + 12
        let size = Self.bubbleSize(Self.longLine)
        let lineHeight = Self.bubbleSize("Hi!").height - verticalPadding
        XCTAssertLessThanOrEqual(size.width, 260 + 13 * 2 + 1)
        // The whole wrapped line fits: at least three lines tall, not one.
        let lines = (size.height - verticalPadding) / lineHeight
        XCTAssertGreaterThanOrEqual(lines, 2.9)
    }

    @MainActor
    func testShortLineGetsAShortBubble() {
        XCTAssertLessThan(Self.bubbleSize("Hi!").width, 120)
    }

    @MainActor
    func testBubbleIsTheSameSizeAtEveryPointOfTheReveal() {
        let start = Date()
        let revealing = Self.bubbleSize(Self.longLine, revealStart: start)
        XCTAssertEqual(revealing, Self.bubbleSize(Self.longLine))
    }

    @MainActor
    private static func bubbleSize(_ text: String, revealStart: Date? = nil) -> CGSize {
        let host = NSHostingView(
            rootView: MascotSpeechBubble(text: text, revealStart: revealStart).fixedSize()
        )
        return host.fittingSize
    }
}
