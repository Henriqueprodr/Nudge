import AppKit
import CoreGraphics

struct ScreenDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
}

@MainActor
protocol ScreenProviding {
    var screens: [ScreenDescriptor] { get }
    var mainScreen: ScreenDescriptor? { get }
    var pointerScreen: ScreenDescriptor? { get }
}

@MainActor
final class SystemScreenProvider: ScreenProviding {
    var screens: [ScreenDescriptor] {
        NSScreen.screens.map(descriptor)
    }

    var mainScreen: ScreenDescriptor? {
        (NSScreen.main ?? NSScreen.screens.first).map(descriptor)
    }

    var pointerScreen: ScreenDescriptor? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) }).map(descriptor)
            ?? mainScreen
    }

    private func descriptor(for screen: NSScreen) -> ScreenDescriptor {
        ScreenDescriptor(
            id: stableIdentifier(for: screen),
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            isMain: screen == NSScreen.main
        )
    }

    private func stableIdentifier(for screen: NSScreen) -> String {
        guard
            let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else {
            return "screen:\(screen.frame.origin.x):\(screen.frame.origin.y)"
        }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }
}
