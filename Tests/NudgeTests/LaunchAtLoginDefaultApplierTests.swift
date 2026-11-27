import XCTest
@testable import Nudge

@MainActor
final class LaunchAtLoginDefaultApplierTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LaunchAtLoginDefaultApplierTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testInstalledCopyEnablesLaunchAtLoginOnce() {
        let manager = RecordingLaunchAtLoginManager()
        let applier = LaunchAtLoginDefaultApplier(
            defaults: defaults,
            bundleURL: URL(fileURLWithPath: "/Applications/Nudge.app")
        )

        XCTAssertTrue(applier.applyIfNeeded(to: manager))
        XCTAssertEqual(manager.enabledRequests, [true])

        manager.status = .notRegistered
        XCTAssertFalse(applier.applyIfNeeded(to: manager))
        XCTAssertEqual(manager.enabledRequests, [true])
    }

    func testUserApplicationsFolderCountsAsInstalled() {
        let applier = LaunchAtLoginDefaultApplier(
            defaults: defaults,
            bundleURL: URL(fileURLWithPath: "/Users/someone/Applications/Nudge.app")
        )
        XCTAssertTrue(applier.isInstalledCopy)
    }

    func testDebugBuildNeverRegisters() {
        let manager = RecordingLaunchAtLoginManager()
        let applier = LaunchAtLoginDefaultApplier(
            defaults: defaults,
            bundleURL: URL(
                fileURLWithPath: "/tmp/.build/DerivedData/Build/Products/Debug/Nudge.app"
            )
        )

        XCTAssertFalse(applier.applyIfNeeded(to: manager))
        XCTAssertTrue(manager.enabledRequests.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: LaunchAtLoginDefaultApplier.appliedDefaultsKey))
    }

    func testAlreadyEnabledLoginItemIsLeftAlone() {
        let manager = RecordingLaunchAtLoginManager()
        manager.status = .enabled
        let applier = LaunchAtLoginDefaultApplier(
            defaults: defaults,
            bundleURL: URL(fileURLWithPath: "/Applications/Nudge.app")
        )

        XCTAssertFalse(applier.applyIfNeeded(to: manager))
        XCTAssertTrue(manager.enabledRequests.isEmpty)
    }
}

@MainActor
private final class RecordingLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginManager.Status = .notRegistered
    private(set) var enabledRequests: [Bool] = []

    func refreshStatus() {}

    func setEnabled(_ isEnabled: Bool) {
        enabledRequests.append(isEnabled)
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}
