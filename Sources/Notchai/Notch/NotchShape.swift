import SwiftUI

/// Kontur der Notch: oben nach außen gewölbte Ecken wie bei der Hardware-Notch, unten abgerundet.
/// Die Wölbungen liegen innerhalb des Rahmens, der Körper ist also um `topCornerRadius` je Seite schmaler.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topCornerRadius) }
        set {
            bottomRadius = newValue.first
            topCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Radien begrenzen, damit die Form auch in kleinen Rahmen nicht umklappt.
        let top = max(0, min(topCornerRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        let left = rect.minX + top
        let right = rect.maxX - top

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left, y: rect.maxY), radius: top)
        p.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.maxY), radius: bottom)
        p.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.minY), radius: bottom)
        p.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: top)
        p.closeSubpath()
        return p
    }
}
