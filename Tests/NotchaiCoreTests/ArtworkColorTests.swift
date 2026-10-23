import Foundation
import Testing
@testable import NotchaiCore

/// Bild aus gleichfarbigen Pixeln: `pixels` gibt an, wie viele Pixel welche Farbe haben.
private func image(_ pixels: [(count: Int, rgb: (UInt8, UInt8, UInt8))]) -> (rgba: [UInt8], width: Int, height: Int) {
    var rgba: [UInt8] = []
    for (count, rgb) in pixels {
        for _ in 0..<count { rgba += [rgb.0, rgb.1, rgb.2, 255] }
    }
    return (rgba, rgba.count / 4, 1)
}

@Test func redCoverGlowsRed() throws {
    let cover = image([(576, (200, 30, 40))])
    let glow = try #require(ArtworkColor.glow(rgba: cover.rgba, width: cover.width, height: cover.height))
    #expect(glow.r > 0.7)
    #expect(glow.g < 0.3 && glow.b < 0.3)
}

@Test func vividBeatsGrayBackground() throws {
    // Ein graues Cover mit einem kleinen blauen Motiv leuchtet blau, nicht grau.
    let cover = image([(520, (128, 128, 128)), (56, (30, 60, 230))])
    let glow = try #require(ArtworkColor.glow(rgba: cover.rgba, width: cover.width, height: cover.height))
    #expect(glow.b > 0.6)
    #expect(glow.b > glow.r + 0.3 && glow.b > glow.g + 0.3)
}

@Test func darkCoverIsBrightened() throws {
    // Ein dunkelrotes Cover leuchtet trotzdem kräftig (ein Leuchten in Fast-Schwarz sähe man nicht).
    let cover = image([(576, (90, 10, 15))])
    let glow = try #require(ArtworkColor.glow(rgba: cover.rgba, width: cover.width, height: cover.height))
    #expect(glow.r > 0.8)
}

@Test func grayCoverHasNoGlow() {
    let cover = image([(300, (128, 128, 128)), (200, (5, 5, 5)), (76, (250, 250, 250))])
    #expect(ArtworkColor.glow(rgba: cover.rgba, width: cover.width, height: cover.height) == nil)
}

@Test func emptyImageHasNoGlow() {
    #expect(ArtworkColor.glow(rgba: [], width: 0, height: 0) == nil)
    // Größe passt nicht zu den Daten.
    #expect(ArtworkColor.glow(rgba: [255, 0, 0, 255], width: 24, height: 24) == nil)
}

@Test func transparentPixelsAreIgnored() {
    var rgba: [UInt8] = []
    for _ in 0..<100 { rgba += [255, 0, 0, 0] }
    #expect(ArtworkColor.glow(rgba: rgba, width: 100, height: 1) == nil)
}
