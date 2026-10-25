import Testing
import CoreGraphics
@testable import LumoCore

let air = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                     topInset: 32, leftAuxWidth: 662, rightAuxWidth: 662)

@Test func notchRectFromAuxAreas() {
    #expect(NotchGeometry.notchRect(air) == CGRect(x: 662, y: 950, width: 188, height: 32))
}
@Test func realDeviceNotchRect() {
    let mac = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                         topInset: 37.5, leftAuxWidth: 856, rightAuxWidth: 856)
    #expect(NotchGeometry.notchRect(mac) == CGRect(x: 856, y: 1205.5, width: 208, height: 37.5))
}
@Test func noNotchGivesNil() {
    let ext = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), topInset: 0, leftAuxWidth: nil, rightAuxWidth: nil)
    #expect(NotchGeometry.notchRect(ext) == nil)
    #expect(NotchGeometry.frame(for: .banner, screen: ext, islandSideWidth: 120) == nil)
}
@Test func idleEqualsNotch() {
    #expect(NotchGeometry.frame(for: .idle, screen: air, islandSideWidth: 120) == NotchGeometry.notchRect(air))
}
@Test func islandGrowsSidewaysOnly() {
    let f = NotchGeometry.frame(for: .island, screen: air, islandSideWidth: 120)!
    #expect(f.width == CGFloat(188 + 240) + 2 * NotchGeometry.islandEdge); #expect(f.height == 32)
    #expect(f.midX == 756); #expect(f.maxY == 982)
}
@Test func bannerIsWideAndShort() {
    let f = NotchGeometry.frame(for: .banner, screen: air, islandSideWidth: 120)!
    #expect(f.width == 640); #expect(f.height == CGFloat(32 + 52)); #expect(f.midX == 756); #expect(f.maxY == 982)
}
@Test func bannerIsClampedToScreen() {
    var small = air; small.frame.size.width = 600
    small.leftAuxWidth = 206; small.rightAuxWidth = 206
    #expect(NotchGeometry.frame(for: .banner, screen: small, islandSideWidth: 120)!.width == 560)
}
@Test func verticalIsTall() {
    let f = NotchGeometry.frame(for: .vertical, screen: air, islandSideWidth: 120)!
    #expect(f.size == CGSize(width: 360, height: 182)); #expect(f.maxY == 982)
}
@Test func panelHeightIsCapped() {
    let f = NotchGeometry.frame(for: .panel(height: 900), screen: air, islandSideWidth: 120)!
    #expect(f.height == 420)
}
@Test func panelBodyIs512Wide() {
    // Körper 512 pt; dazu oben je Seite die Wölbung zum Bildschirmrand.
    let f = NotchGeometry.frame(for: .panel(height: 150), screen: air, islandSideWidth: 120)!
    #expect(NotchGeometry.panelEar == 7)
    #expect(f.width - 2 * NotchGeometry.panelEar == 512)
}
@Test func bannerIsNeverNarrowerThanIsland() {
    // Klappt eine breite Island zum Banner auf, darf die Form nicht schmaler werden.
    let f = NotchGeometry.frame(for: .banner, screen: air, islandSideWidth: 300)!
    #expect(f.width == CGFloat(188 + 600) + 2 * NotchGeometry.islandEdge); #expect(f.midX == 756)
}
@Test func compactIsSlimmerThanIsland() {
    // Musik eingeklappt: so hoch wie die Notch, links Cover, rechts Balken, schmaler als die Island.
    let compact = NotchGeometry.frame(for: .compact, screen: air, islandSideWidth: 120)!
    let island = NotchGeometry.frame(for: .island, screen: air, islandSideWidth: 120)!
    #expect(compact.width == 188 + 2 * NotchGeometry.compactSideWidth)
    #expect(compact.width < island.width)
    #expect(compact.height == 32); #expect(compact.midX == 756); #expect(compact.maxY == 982)
}
