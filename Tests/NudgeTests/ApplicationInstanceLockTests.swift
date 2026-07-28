import XCTest
@testable import Nudge

final class ApplicationInstanceLockTests: XCTestCase {
    func testOnlyOneLockOwnerExistsForAnApplicationIdentifier() throws {
        let identifier = "com.local.Nudge.tests.\(UUID().uuidString)"
        let firstLock = try XCTUnwrap(ApplicationInstanceLock(identifier: identifier))

        XCTAssertNil(ApplicationInstanceLock(identifier: identifier))
        withExtendedLifetime(firstLock) {}
    }

    func testLockIsReleasedWhenItsOwnerIsDestroyed() throws {
        let identifier = "com.local.Nudge.tests.\(UUID().uuidString)"
        do {
            let firstLock = try XCTUnwrap(ApplicationInstanceLock(identifier: identifier))
            withExtendedLifetime(firstLock) {}
        }

        XCTAssertNotNil(ApplicationInstanceLock(identifier: identifier))
    }
}
