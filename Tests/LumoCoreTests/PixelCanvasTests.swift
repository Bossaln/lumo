import Foundation
import Testing
@testable import LumoCore

@Test func fillAndBlend() {
    var canvas = PixelCanvas(width: 4, height: 3)
    canvas.fill(0, 0, 4, 3, RGBA(200, 0, 0))
    #expect(canvas[1, 1] == RGBA(200, 0, 0))
    // Halb durchsichtiges Blau mischt sich mit dem Rot darunter.
    canvas.set(1, 1, RGBA(0, 0, 200, 128))
    let mixed = canvas[1, 1]
    #expect(mixed.r > 90 && mixed.r < 110 && mixed.b > 90 && mixed.b < 110 && mixed.a == 255)
    // Außerhalb passiert nichts (und es stürzt nichts ab).
    canvas.set(-1, 7, RGBA(0, 255, 0))
    canvas.fill(3, 2, 10, 10, RGBA(0, 255, 0))
    #expect(canvas[3, 2] == RGBA(0, 255, 0))
    #expect(canvas[9, 9] == .clear)
}

@Test func spriteUsesPalette() {
    var canvas = PixelCanvas(width: 3, height: 2)
    canvas.sprite(["ab.", ".a."], palette: ["a": RGBA(255, 0, 0), "b": RGBA(0, 255, 0)], at: 0, 0)
    #expect(canvas[0, 0] == RGBA(255, 0, 0))
    #expect(canvas[1, 0] == RGBA(0, 255, 0))
    #expect(canvas[2, 0] == .clear)  // „.“ bleibt durchsichtig
    #expect(canvas[1, 1] == RGBA(255, 0, 0))
    // Gespiegelt (Figur schaut nach links).
    var flipped = PixelCanvas(width: 3, height: 2)
    flipped.sprite(["ab.", ".a."], palette: ["a": RGBA(255, 0, 0), "b": RGBA(0, 255, 0)], at: 0, 0, flipped: true)
    #expect(flipped[2, 0] == RGBA(255, 0, 0))
    #expect(flipped[1, 0] == RGBA(0, 255, 0))
}

@Test func fontHasSlashedO() {
    // Für „Bøssa“ braucht die Schrift ein Ø, das sich vom O unterscheidet.
    let slashed = PixelFont.glyph("Ø")
    let plain = PixelFont.glyph("O")
    #expect(slashed != nil && plain != nil && slashed != plain)
    #expect(PixelFont.glyph("A")?.count == PixelFont.height)
}

@Test func textIsClippedAndMeasured() {
    var canvas = PixelCanvas(width: 10, height: 5)
    let width = canvas.text("BØSSA", at: 6, 0, color: RGBA(255, 255, 255))
    #expect(width == 5 * (PixelFont.width + 1) - 1)
    #expect(PixelFont.measure("BØSSA") == width)
    // Die ersten Spalten des B sind gezeichnet, der Rest liegt außerhalb.
    #expect(canvas[6, 0] == RGBA(255, 255, 255))
}

@Test func bytesAreRGBARowMajor() {
    var canvas = PixelCanvas(width: 2, height: 1)
    canvas.set(1, 0, RGBA(1, 2, 3, 255))
    #expect(canvas.rgbaBytes == [0, 0, 0, 0, 1, 2, 3, 255])
}

@Test func polygonFillsInsideOnly() {
    var canvas = PixelCanvas(width: 6, height: 6)
    canvas.polygon([(0, 0), (6, 0), (0, 6)], RGBA(255, 0, 0))
    #expect(canvas[0, 0] == RGBA(255, 0, 0))
    #expect(canvas[5, 5] == .clear)
    // Ganz außerhalb: nichts passiert, kein Absturz.
    canvas.polygon([(-20, -20), (-10, -20), (-10, -10)], RGBA(0, 255, 0))
    canvas.polygon([(40, 40), (50, 40), (50, 50)], RGBA(0, 255, 0))
}
