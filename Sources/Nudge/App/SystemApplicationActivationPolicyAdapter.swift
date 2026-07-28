import AppKit

@MainActor
final class SystemApplicationActivationPolicyAdapter: ApplicationActivationPolicyApplying {
    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }
}
