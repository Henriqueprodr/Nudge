import XCTest
@testable import Nudge

final class AppMenuActionTests: XCTestCase {
    func testMenuContainsRequiredActionsInOrder() {
        XCTAssertEqual(
            AppMenuAction.allCases.map(\.rawValue),
            [
                "Show Test Reminder",
                "Show Test Task Nag",
                "Summon the Bird",
                "Show Task Panel",
                "Hide Task Panel",
                "Reset Task Panel Position",
                "Refresh Tasks",
                "Mute the Bird for 1 Hour",
                "Unmute the Bird",
                "Settings",
                "Quit",
            ]
        )
    }
}
