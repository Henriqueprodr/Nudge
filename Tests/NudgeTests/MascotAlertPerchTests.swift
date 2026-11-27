import CoreGraphics
import XCTest
@testable import Nudge

/// The bird clings to the alert's left edge, never under the menu bar, and its bubble grows away
/// from the menu bar.
final class MascotAlertPerchTests: XCTestCase {
    private let birdSize = CGSize(width: 54 * 0.8, height: 54 * 0.8 * 1.25)

    func testLaptopPerchGripsTheCardsLeftEdgeBelowTheMenuBarWithBubbleBeside() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let card = Self.card(width: 700, height: 80, in: visible)
        let perch = try XCTUnwrap(MascotAlertPerch(
            card: card, screenFrame: screen, visibleFrame: visible, birdSize: birdSize
        ))

        let cardLeft = card.minX - screen.minX
        let gripX = perch.birdFrame.minX + birdSize.width * BirdShapes.clingGrip.x
        XCTAssertEqual(gripX, cardLeft + MascotAlertPerch.gripOverlap, accuracy: 0.5)
        XCTAssertLessThan(perch.birdFrame.minX, cardLeft, "The bird's body is beside the card")

        let cardTop = screen.maxY - card.maxY
        let cardBottom = screen.maxY - card.minY
        XCTAssertGreaterThan(perch.birdFrame.midY, cardTop)
        XCTAssertLessThan(perch.birdFrame.midY, cardBottom)

        let menuBarBottom = screen.maxY - visible.maxY
        XCTAssertGreaterThanOrEqual(perch.birdFrame.minY, menuBarBottom + MascotAlertPerch.topMargin)
        XCTAssertEqual(perch.position, CGPoint(x: perch.birdFrame.midX, y: perch.birdFrame.maxY))
        XCTAssertEqual(perch.bubblePlacement, .leading)
    }

    func testNarrowerScreenPutsTheBubbleUnderTheCard() throws {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 776)
        let card = Self.card(width: 700, height: 90, in: visible)
        let perch = try XCTUnwrap(MascotAlertPerch(
            card: card, screenFrame: screen, visibleFrame: visible, birdSize: birdSize
        ))
        guard case let .belowCard(topY) = perch.bubblePlacement else {
            return XCTFail("Expected the bubble under the card, got \(perch.bubblePlacement)")
        }
        XCTAssertGreaterThan(topY, screen.maxY - card.minY)
    }

    func testCardFillingTheScreenLeavesNoRoomSoTheBirdUsesTheDock() {
        let screen = CGRect(x: 0, y: 0, width: 640, height: 480)
        let visible = CGRect(x: 0, y: 0, width: 640, height: 456)
        let card = Self.card(width: 624, height: 90, in: visible)
        XCTAssertNil(MascotAlertPerch(
            card: card, screenFrame: screen, visibleFrame: visible, birdSize: birdSize
        ))
    }

    func testSecondaryDisplayUsesWindowLocalCoordinates() throws {
        let screen = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let visible = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let card = Self.card(width: 700, height: 80, in: visible)
        let perch = try XCTUnwrap(MascotAlertPerch(
            card: card, screenFrame: screen, visibleFrame: visible, birdSize: birdSize
        ))
        XCTAssertGreaterThan(perch.birdFrame.minX, 0)
        XCTAssertLessThan(perch.birdFrame.maxX, screen.width)
        XCTAssertGreaterThan(perch.birdFrame.minY, screen.maxY - visible.maxY)
    }

    /// The alert's real resting frame, from the same placement the overlay controller uses.
    private static func card(width: CGFloat, height: CGFloat, in visible: CGRect) -> CGRect {
        ScreenPlacement.reminderStripFrame(
            contentSize: CGSize(width: width, height: height),
            in: visible,
            topInset: ReminderStripStyle.screenTopInset,
            horizontalInset: ReminderStripStyle.screenHorizontalInset
        )
    }
}
