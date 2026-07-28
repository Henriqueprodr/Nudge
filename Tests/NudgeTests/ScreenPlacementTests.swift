import CoreGraphics
import XCTest
@testable import Nudge

final class ScreenPlacementTests: XCTestCase {
    func testCornerFramesUseEveryVisibleFrameCorner() {
        let visibleFrame = CGRect(x: -1440, y: 25, width: 1440, height: 875)
        let contentSize = CGSize(width: 320, height: 240)
        let inset: CGFloat = 16

        XCTAssertEqual(
            ScreenPlacement.cornerFrame(
                contentSize: contentSize,
                in: visibleFrame,
                corner: .topLeading,
                edgeInset: inset
            ),
            CGRect(x: -1424, y: 644, width: 320, height: 240)
        )
        XCTAssertEqual(
            ScreenPlacement.cornerFrame(
                contentSize: contentSize,
                in: visibleFrame,
                corner: .topTrailing,
                edgeInset: inset
            ),
            CGRect(x: -336, y: 644, width: 320, height: 240)
        )
        XCTAssertEqual(
            ScreenPlacement.cornerFrame(
                contentSize: contentSize,
                in: visibleFrame,
                corner: .bottomLeading,
                edgeInset: inset
            ),
            CGRect(x: -1424, y: 41, width: 320, height: 240)
        )
        XCTAssertEqual(
            ScreenPlacement.cornerFrame(
                contentSize: contentSize,
                in: visibleFrame,
                corner: .bottomTrailing,
                edgeInset: inset
            ),
            CGRect(x: -336, y: 41, width: 320, height: 240)
        )
    }

    func testCornerFrameClampsOversizedContentInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 300, height: 200)

        let frame = ScreenPlacement.cornerFrame(
            contentSize: CGSize(width: 900, height: 700),
            in: visibleFrame,
            corner: .bottomTrailing,
            edgeInset: 16
        )

        XCTAssertEqual(frame, visibleFrame)
    }

    func testCustomPositionRoundTripsAndStaysInsideVisibleFrame() {
        let visibleFrame = CGRect(x: -1440, y: 25, width: 1440, height: 875)
        let position = TaskPanelState.NormalizedPosition(x: 0.25, y: 0.75)
        let frame = ScreenPlacement.customFrame(
            contentSize: CGSize(width: 346, height: 400),
            in: visibleFrame,
            normalizedPosition: position,
            edgeInset: 16
        )

        XCTAssertTrue(visibleFrame.contains(frame))
        let restored = ScreenPlacement.normalizedPosition(
            for: frame,
            in: visibleFrame,
            edgeInset: 16
        )
        XCTAssertEqual(restored.x, position.x, accuracy: 0.0001)
        XCTAssertEqual(restored.y, position.y, accuracy: 0.0001)
    }

    func testCustomPositionClampsInvalidNormalizedValues() {
        let position = TaskPanelState.NormalizedPosition(x: -3, y: 8)

        XCTAssertEqual(position.x, 0)
        XCTAssertEqual(position.y, 1)
    }

    func testReminderStripRestsInUpperCenterOfVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1200, height: 760)

        let frame = ScreenPlacement.reminderStripFrame(
            contentSize: CGSize(width: 480, height: 96),
            in: visibleFrame,
            topInset: 8,
            horizontalInset: 8
        )

        XCTAssertEqual(frame, CGRect(x: 360, y: 696, width: 480, height: 96))
        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testReminderStripCentersOnNegativeCoordinateDisplay() {
        let visibleFrame = CGRect(x: -1920, y: 24, width: 1440, height: 876)

        let frame = ScreenPlacement.reminderStripFrame(
            contentSize: CGSize(width: 560, height: 100),
            in: visibleFrame,
            topInset: 8,
            horizontalInset: 8
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.maxY, visibleFrame.maxY - 8)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testReminderStripStaysInsideNarrowAndShortVisibleFrames() {
        let narrowFrame = CGRect(x: -1920, y: 25, width: 320, height: 120)

        let frame = ScreenPlacement.reminderStripFrame(
            contentSize: CGSize(width: 480, height: 200),
            in: narrowFrame,
            topInset: 8,
            horizontalInset: 8
        )

        XCTAssertEqual(frame, CGRect(x: -1912, y: 25, width: 304, height: 120))
        XCTAssertTrue(narrowFrame.contains(frame))
    }

}
