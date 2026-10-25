import Testing
@testable import LumoCore

@Test func glowPulsesWithTwoPointTwoSecondCycle() {
    #expect(GlowPulse.cycle == 2.2)
    #expect(abs(GlowPulse.level(at: 0)) < 0.0001)
    #expect(abs(GlowPulse.level(at: 1.1) - 1) < 0.0001)
    #expect(abs(GlowPulse.level(at: 0.55) - 0.5) < 0.0001)
    #expect(abs(GlowPulse.level(at: 2.2)) < 0.0001)
    #expect(abs(GlowPulse.level(at: 2.2 * 1000 + 1.1) - 1) < 0.0001)
}

@Test func glowStrengthFollowsSettings() {
    // 0,6 ist der Standard und entspricht den Werten aus dem Entwurf.
    #expect(GlowPulse.strength(intensity: 0.6, enabled: true) == 1)
    #expect(GlowPulse.strength(intensity: 0.3, enabled: true) == 0.5)
    #expect(GlowPulse.strength(intensity: 0.6, enabled: false) == 0)
    #expect(GlowPulse.strength(intensity: 0, enabled: true) == 0)
    #expect(GlowPulse.strength(intensity: 7, enabled: true) == GlowPulse.strength(intensity: 1, enabled: true))
}
