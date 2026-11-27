import SwiftUI

/// A hand-drawn wavy underline used to flag overdue tasks.
struct WavyUnderline: Shape {
    var amplitude: CGFloat = 1.6
    var wavelength: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let next = min(x + wavelength / 2, rect.maxX)
            path.addQuadCurve(
                to: CGPoint(x: next, y: midY),
                control: CGPoint(x: (x + next) / 2, y: midY + (up ? -amplitude : amplitude) * 2)
            )
            up.toggle()
            x = next
        }
        return path
    }
}
