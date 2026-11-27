import SwiftUI

/// Vector parts of the Nudge bird, traced from `brand/` and drawn in a 100 × 125 unit box.
///
/// The parts are separate so the animator can swing legs, flap the wing, and swap the head
/// between profile and facing-the-viewer poses. Every shape scales to the rect it is given.
enum BirdShapes {
    static let canvas = CGSize(width: 100, height: 125)

    /// Maps a point in the 100 × 125 canvas into `rect`.
    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x / canvas.width * rect.width,
            y: rect.minY + y / canvas.height * rect.height
        )
    }
}

/// Head and body silhouette, beak excluded.
struct BirdBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(80, 25))
        // Chest down to the belly.
        path.addCurve(to: p(70, 70), control1: p(79, 42), control2: p(77, 58))
        path.addCurve(to: p(48, 84), control1: p(65, 79), control2: p(57, 84))
        path.addCurve(to: p(30, 79), control1: p(41, 84), control2: p(35, 82))
        // Under the wing to the lower tail feather.
        path.addCurve(to: p(10, 74), control1: p(24, 79), control2: p(14, 79))
        path.addCurve(to: p(9, 66), control1: p(6, 72), control2: p(5, 68))
        // Upper tail feather and up the back.
        path.addCurve(to: p(6, 61), control1: p(4, 65), control2: p(3, 62))
        path.addCurve(to: p(28, 45), control1: p(10, 56), control2: p(21, 51))
        path.addCurve(to: p(40, 22), control1: p(36, 38), control2: p(37, 30))
        // Over the crown.
        path.addCurve(to: p(64, 3), control1: p(43, 9), control2: p(53, 3))
        path.addCurve(to: p(81, 18), control1: p(74, 3), control2: p(80, 10))
        path.addLine(to: p(80, 25))
        path.closeSubpath()
        return path
    }
}

/// The side-profile beak pointing right.
struct BirdBeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(80.5, 17))
        path.addLine(to: p(97, 22.5))
        path.addQuadCurve(to: p(96.5, 25), control: p(99, 23.5))
        path.addLine(to: p(80, 31))
        path.closeSubpath()
        return path
    }
}

/// The small front-facing beak used when the bird looks at the viewer.
struct BirdFrontBeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(63, 24))
        path.addLine(to: p(71, 24))
        path.addLine(to: p(67, 31))
        path.closeSubpath()
        return path
    }
}

/// The wing stroke and its two lower feathers. `lift` raises the wing tip for flapping,
/// from 0 (folded) to 1 (fully raised).
struct BirdWingShape: Shape {
    var lift: CGFloat = 0

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        let raise = lift * 34
        var path = Path()
        path.move(to: p(51, 51))
        path.addCurve(
            to: p(26, 78 - raise),
            control1: p(51, 64 - raise * 0.3),
            control2: p(40, 76 - raise * 0.8)
        )
        // Feather notches along the lower back.
        path.move(to: p(30, 63 - raise * 0.5))
        path.addCurve(to: p(10, 66 - raise), control1: p(25, 67 - raise * 0.6), control2: p(16, 68 - raise))
        return path
    }
}

/// One thin leg from the belly to the foot. `swing` tilts it, -1...1.
struct BirdLegShape: Shape {
    var hipX: CGFloat
    var footX: CGFloat
    var swing: CGFloat = 0

    var animatableData: CGFloat {
        get { swing }
        set { swing = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(hipX, 82))
        path.addLine(to: p(footX + swing * 8, 117))
        return path
    }
}

/// An oval foot whose heel sits under its leg; toes point forward (right).
struct BirdFootShape: Shape {
    var heelX: CGFloat
    /// Where the toes point relative to the heel, in canvas units (negative is backward).
    var reach: CGFloat
    var swing: CGFloat = 0

    var animatableData: CGFloat {
        get { swing }
        set { swing = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let heel = heelX + swing * 8
        let minX = min(heel, heel + reach)
        let topLeft = BirdShapes.point(minX - 2, 116, in: rect)
        let bottomRight = BirdShapes.point(minX + abs(reach) + 2, 122.5, in: rect)
        return Path(ellipseIn: CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ))
    }
}

/// The open wing shown while flying, hinged at the shoulder. `lift` is 0 (level) ... 1 (up).
struct BirdFlyingWingShape: Shape {
    var lift: CGFloat = 0

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { BirdShapes.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(52, 46))
        path.addCurve(to: p(14, 40), control1: p(42, 34), control2: p(25, 32))
        path.addCurve(to: p(20, 48), control1: p(11, 44), control2: p(14, 47))
        path.addCurve(to: p(12, 54), control1: p(13, 50), control2: p(10, 52))
        path.addCurve(to: p(50, 60), control1: p(22, 62), control2: p(40, 64))
        path.closeSubpath()
        let shoulder = p(52, 52)
        let angle = lift * .pi / 3.2
        return path.applying(
            CGAffineTransform(translationX: shoulder.x, y: shoulder.y)
                .rotated(by: angle)
                .translatedBy(x: -shoulder.x, y: -shoulder.y)
        )
    }
}
