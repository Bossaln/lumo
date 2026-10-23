import CoreGraphics
import Testing
@testable import NotchaiCore

@Test func growingIsExpanding() {
    #expect(NotchMotion.between(CGSize(width: 200, height: 32), CGSize(width: 512, height: 150)) == .expand)
    // Breiter, aber flacher (Panel → Banner) zählt als Aufklappen.
    #expect(NotchMotion.between(CGSize(width: 512, height: 150), CGSize(width: 640, height: 84)) == .expand)
}

@Test func shrinkingIsCollapsing() {
    #expect(NotchMotion.between(CGSize(width: 512, height: 150), CGSize(width: 200, height: 32)) == .collapse)
    #expect(NotchMotion.between(CGSize(width: 512, height: 150), CGSize(width: 512, height: 120)) == .collapse)
}

@Test func collapseNeverBounces() {
    // Beim Zuklappen darf die Form nicht unter die Hardware-Notch schwingen.
    let spring = NotchSpring(bounce: 1)
    #expect(spring.collapseDampingFraction >= 1)
    #expect(spring.collapseResponse > 0.3 && spring.collapseResponse < 0.6)
}

@Test func frameNeverSmallerThanNotch() {
    let notch = CGSize(width: 200, height: 32)
    #expect(NotchMotion.clamped(CGSize(width: 180, height: 28), notch: notch) == notch)
    #expect(NotchMotion.clamped(CGSize(width: 400, height: 28), notch: notch) == CGSize(width: 400, height: 32))
    #expect(NotchMotion.clamped(CGSize(width: 400, height: 90), notch: nil) == CGSize(width: 400, height: 90))
}
