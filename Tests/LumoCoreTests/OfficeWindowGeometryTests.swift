import CoreGraphics
import Testing
@testable import LumoCore

// 16"-MacBook: 1728 × 1117 pt, Notch 32 pt hoch.
private let big = CGRect(x: 0, y: 0, width: 1728, height: 1117)
// 14"-MacBook: 1512 × 982 pt.
private let small = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func officeWindowUsesBaseSizeWhenItFits() {
    let g = OfficeWindowGeometry.frame(screen: big, topInset: 32, centerX: 864, officeScale: 0.6, backingScale: 2)
    // 4,25 pt × 0,6 = 2,55 → auf ganze Geräte-Pixel (½ pt) abgerundet: 2,5 pt je Pixel.
    #expect(g.pixelScale == 2.5)
    #expect(g.frame.width == 352 * 2.5)
    #expect(g.frame.height == 254 * 2.5)
}

@Test func officeWindowShrinksToFitTheScreen() {
    let g = OfficeWindowGeometry.frame(screen: small, topInset: 32, centerX: 756, officeScale: 1, backingScale: 2)
    // Unter der Notch bleiben 982 − 32 − 2 × 8 = 934 pt; 934 / 254 = 3,67 → 3,5 pt.
    #expect(g.pixelScale == 3.5)
    #expect(g.frame.height <= 982 - 32)
    #expect(g.frame.width <= 1512)
}

@Test func officeWindowHangsBelowTheNotchCentered() {
    let g = OfficeWindowGeometry.frame(screen: big, topInset: 32, centerX: 864, officeScale: 0.6, backingScale: 2)
    #expect(g.frame.maxY == 1117 - 32 - OfficeWindowGeometry.gap)
    #expect(g.frame.midX == 864)
}

@Test func officeWindowStaysOnScreenHorizontally() {
    let g = OfficeWindowGeometry.frame(screen: big, topInset: 32, centerX: 100, officeScale: 0.6, backingScale: 2)
    #expect(g.frame.minX == OfficeWindowGeometry.gap)
}

@Test func officeWindowNeverGetsTiny() {
    let g = OfficeWindowGeometry.frame(screen: CGRect(x: 0, y: 0, width: 300, height: 200), topInset: 0, centerX: 150,
                                       officeScale: 0.1, backingScale: 1)
    #expect(g.pixelScale == 1)
}
