import XCTest
@testable import Nudge

final class SingleApplicationInstancePolicyTests: XCTestCase {
    func testOnlyOldestNudgeProcessContinuesLaunching() {
        XCTAssertTrue(
            SingleApplicationInstancePolicy.shouldContinueLaunching(
                currentProcessIdentifier: 100,
                runningProcessIdentifiers: [100, 200]
            )
        )
        XCTAssertFalse(
            SingleApplicationInstancePolicy.shouldContinueLaunching(
                currentProcessIdentifier: 200,
                runningProcessIdentifiers: [100, 200]
            )
        )
    }

    func testCurrentProcessContinuesWhenItIsTheOnlyInstance() {
        XCTAssertTrue(
            SingleApplicationInstancePolicy.shouldContinueLaunching(
                currentProcessIdentifier: 100,
                runningProcessIdentifiers: [100]
            )
        )
    }
}
