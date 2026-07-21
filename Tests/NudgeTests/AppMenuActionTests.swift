import XCTest
@testable import Nudge

final class AppMenuActionTests: XCTestCase {
    func testPhaseZeroMenuContainsRequiredActionsInOrder() {
        XCTAssertEqual(
            AppMenuAction.allCases.map(\.rawValue),
            [
                "Show Test Reminder",
                "Show Task Panel",
                "Hide Task Panel",
                "Refresh Tasks",
                "Settings",
                "Quit",
            ]
        )
    }
}
