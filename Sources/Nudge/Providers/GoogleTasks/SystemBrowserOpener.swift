import AppKit
import Foundation

@MainActor
protocol SystemBrowserOpening: AnyObject {
    func open(_ url: URL) -> Bool
}

@MainActor
final class SystemBrowserOpener: SystemBrowserOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
