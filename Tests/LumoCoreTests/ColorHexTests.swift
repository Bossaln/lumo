import Testing
@testable import LumoCore

@Test func parsesSixDigitHex() {
    #expect(ColorHex.parse("#E0764A") == RGB(r: 224/255, g: 118/255, b: 74/255))
    #expect(ColorHex.parse("e0764a") == ColorHex.parse("#E0764A"))
}
@Test func rejectsInvalidHex() {
    #expect(ColorHex.parse("#XYZ") == nil)
    #expect(ColorHex.parse("") == nil)
}
@Test func formatsUppercaseWithHash() {
    #expect(ColorHex.format(RGB(r: 0, g: 0, b: 0)) == "#000000")
    #expect(ColorHex.format(ColorHex.parse("#8aa2ff")!) == "#8AA2FF")
}
