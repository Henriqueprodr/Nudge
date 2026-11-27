import AVFoundation
import Foundation
import XCTest
@testable import Nudge

final class MascotTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    // MARK: Ground placement

    func testVisibleBottomDockIsWalkedAlongItsTopEdgeWithinItsWidth() {
        let ground = MascotGround.resolve(
            frame: screen,
            visibleFrame: CGRect(x: 0, y: 75, width: 1728, height: 1009),
            dock: DockGeometry(edge: .bottom, autohides: false, estimatedLength: 800)
        )

        XCTAssertTrue(ground.isOnDock)
        XCTAssertEqual(ground.y, 75)
        XCTAssertEqual(ground.xRange.lowerBound, 864 - 400 + MascotGround.dockEndInset)
        XCTAssertEqual(ground.xRange.upperBound, 864 + 400 - MascotGround.dockEndInset)
    }

    func testAutoHiddenDockFallsBackToTheScreenBottom() {
        let ground = MascotGround.resolve(
            frame: screen,
            visibleFrame: CGRect(x: 0, y: 4, width: 1728, height: 1080),
            dock: DockGeometry(edge: .bottom, autohides: true, estimatedLength: nil)
        )

        XCTAssertFalse(ground.isOnDock)
        XCTAssertEqual(ground.y, 4)
        XCTAssertEqual(ground.xRange.lowerBound, MascotGround.screenEdgeInset)
    }

    func testSideDockWalksAlongTheBottomOfTheVisibleArea() {
        let ground = MascotGround.resolve(
            frame: screen,
            visibleFrame: CGRect(x: 80, y: 0, width: 1648, height: 1084),
            dock: DockGeometry(edge: .left, autohides: false, estimatedLength: nil)
        )

        XCTAssertFalse(ground.isOnDock)
        XCTAssertEqual(ground.y, 0)
        XCTAssertEqual(ground.xRange.lowerBound, 80 + MascotGround.screenEdgeInset)
        XCTAssertEqual(ground.xRange.upperBound, 1728 - MascotGround.screenEdgeInset)
    }

    func testOversizedDockEstimateIsClampedToTheScreen() {
        let ground = MascotGround.resolve(
            frame: screen,
            visibleFrame: CGRect(x: 0, y: 75, width: 1728, height: 1009),
            dock: DockGeometry(edge: .bottom, autohides: false, estimatedLength: 5_000)
        )
        XCTAssertGreaterThanOrEqual(ground.xRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(ground.xRange.upperBound, 1728)
    }

    // MARK: Lines

    private let book = MascotLineBook(lines: [
        "idle": ["mild": ["m1"], "spicy": ["s1"], "unhinged": ["u1"]],
        "taskOverdue": ["mild": ["\"{task}\" is {days} days late."]],
    ])

    func testSpiceLevelControlsWhichLinesAreEligible() {
        XCTAssertEqual(book.candidates(for: .idle, spice: .mild), ["m1"])
        XCTAssertEqual(Set(book.candidates(for: .idle, spice: .spicy)), ["m1", "s1"])
        XCTAssertFalse(book.candidates(for: .idle, spice: .spicy).contains("u1"))
        XCTAssertEqual(Set(book.candidates(for: .idle, spice: .unhinged)), ["m1", "s1", "u1"])
        // The chosen level is weighted more heavily than milder ones.
        let unhinged = book.candidates(for: .idle, spice: .unhinged)
        XCTAssertGreaterThan(unhinged.filter { $0 == "u1" }.count, unhinged.filter { $0 == "m1" }.count)
    }

    func testPlaceholdersAreFilledAndMissingCategoriesFallBackToIdle() {
        let line = book.line(
            for: .taskOverdue,
            spice: .unhinged,
            substitutions: ["task": "Taxes", "days": "4"],
            randomUnit: { 0 }
        )
        XCTAssertEqual(line, "\"Taxes\" is 4 days late.")
        XCTAssertEqual(book.line(for: .signedOut, spice: .mild, randomUnit: { 0 }), "m1")
    }

    func testRecentLinesAreAvoidedWhenAlternativesExist() {
        let line = book.line(for: .idle, spice: .spicy, avoiding: ["m1"], randomUnit: { 0 })
        XCTAssertEqual(line, "s1")
    }

    func testBundledLinesCoverEveryCategoryAtEverySpiceLevel() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MascotLines", withExtension: "json"))
        let bundled = MascotLineBook.load(bundle: .main, userFileURL: nil)
        XCTAssertNotNil(url)
        for category in MascotLineCategory.allCases {
            XCTAssertFalse(
                bundled.candidates(for: category, spice: .mild).isEmpty,
                "\(category) has no mild lines"
            )
            XCTAssertGreaterThan(
                Set(bundled.candidates(for: category, spice: .unhinged)).count,
                Set(bundled.candidates(for: category, spice: .mild)).count,
                "\(category) has no spicier lines"
            )
        }
    }

    func testToneMapsToLineCategories() {
        XCTAssertEqual(MascotLineCategory(tone: .calendar), .calendarSoon)
        XCTAssertEqual(MascotLineCategory(tone: .actionNeeded), .signedOut)
        XCTAssertEqual(MascotLineCategory(tone: .task(.overdue)), .taskOverdue)
        XCTAssertEqual(MascotLineCategory(tone: .task(.ancient)), .taskAncient)
    }

    // MARK: Settings and sound

    func testMascotSettingsClampAndDoNotDisturb() {
        var settings = MascotSettings.defaultValue
        settings.idleVisitIntervalMinutes = 2
        XCTAssertEqual(settings.validated.idleVisitIntervalMinutes, 15)

        let now = Date(timeIntervalSince1970: 1_000)
        settings.doNotDisturbUntil = now.addingTimeInterval(60)
        XCTAssertTrue(settings.isQuiet(at: now))
        XCTAssertFalse(settings.isQuiet(at: now.addingTimeInterval(120)))
        settings.isEnabled = false
        XCTAssertTrue(settings.isQuiet(at: now.addingTimeInterval(120)))
    }

    @MainActor
    func testWhistleBuffersAreShortAndNonSilent() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        for call in BirdWhistleSynth.Call.allCases {
            let buffer = try XCTUnwrap(BirdWhistleSynth.buffer(for: call, format: format))
            let seconds = Double(buffer.frameLength) / format.sampleRate
            XCTAssertLessThan(seconds, 1.5)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.3)
            XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 1, 1)
        }
    }

    func testQuotedTitlesAreShortenedAtAWordBoundary() {
        XCTAssertEqual(MascotLineBook.shortened("Taxes"), "Taxes")
        XCTAssertEqual(MascotLineBook.shortened("  Taxes  "), "Taxes")
        let long = "Finish the extremely long quarterly report draft and send it to the whole team"
        let short = MascotLineBook.shortened(long)
        XCTAssertEqual(short, "Finish the extremely long quarterly report draft…")
        XCTAssertLessThanOrEqual(short.count, 49)
        let unbroken = String(repeating: "x", count: 80)
        XCTAssertEqual(MascotLineBook.shortened(unbroken), String(repeating: "x", count: 48) + "…")
    }

    @MainActor
    func testReadingTimeGrowsWithTheLineAndStaysBounded() {
        XCTAssertEqual(MascotController.readingTime(for: "Hi!", revealDuration: 0.8), 2.5)
        let long = String(repeating: "pecking ", count: 40)
        XCTAssertEqual(MascotController.readingTime(for: long, revealDuration: 2.6), 7)
    }
}
