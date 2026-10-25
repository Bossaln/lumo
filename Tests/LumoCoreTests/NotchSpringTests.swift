import Foundation
import Testing
@testable import LumoCore

@Test func noBounceIsCalm() {
    let spring = NotchSpring(bounce: 0)
    #expect(spring.dampingFraction >= 0.85)
}

@Test func defaultBounceIsMinimal() {
    // Wie die Dynamic Island: sichtbar, aber nur ein kleines Nachfedern.
    let spring = NotchSpring(bounce: AppSettings.default.notchBounce)
    #expect(spring.dampingFraction > 0.68 && spring.dampingFraction < 0.8)
    #expect(spring.response > 0.3 && spring.response < 0.45)
}

@Test func moreBounceMeansLessDamping() {
    #expect(NotchSpring(bounce: 1).dampingFraction < NotchSpring(bounce: 0.5).dampingFraction)
    // Auch bei voller Stärke bleibt es eine Feder, die sich schnell beruhigt.
    #expect(NotchSpring(bounce: 1).dampingFraction >= 0.5)
}

@Test func bounceOutsideRangeIsClamped() throws {
    #expect(NotchSpring(bounce: -3) == NotchSpring(bounce: 0))
    #expect(NotchSpring(bounce: 7) == NotchSpring(bounce: 1))
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"notchBounce":4}"#.utf8))
    #expect(decoded.notchBounce == 1)
}
