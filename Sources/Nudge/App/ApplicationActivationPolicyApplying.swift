@MainActor
protocol ApplicationActivationPolicyApplying {
    @discardableResult
    func setDockIconVisible(_ isVisible: Bool) -> Bool
}
