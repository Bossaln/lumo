import Foundation
import Testing
@testable import LumoCore

@Test func appleScriptDataIsDecoded() {
    // So gibt `osascript` Bilddaten aus (Cover von Musik).
    #expect(AppleScriptData.parse("«data PNGf89504E47»\n") == Data([0x89, 0x50, 0x4E, 0x47]))
    #expect(AppleScriptData.parse("«data tdtaffd8ffe0»") == Data([0xFF, 0xD8, 0xFF, 0xE0]))
}

@Test func otherAppleScriptOutputIsNoData() {
    #expect(AppleScriptData.parse("") == nil)
    #expect(AppleScriptData.parse("https://i.scdn.co/image/ab67616d") == nil)
    #expect(AppleScriptData.parse("«data PNGf89504E4»") == nil)  // ungerade Zahl an Ziffern
    #expect(AppleScriptData.parse("«data PNGfXYZW»") == nil)
}

@Test func musicGlowBreathesSlowerThanSignal() {
    #expect(GlowPulse.musicCycle > GlowPulse.cycle)
    // Nach einem halben Zyklus ist das Leuchten am hellsten, in beiden Takten.
    #expect(abs(GlowPulse.level(at: GlowPulse.musicCycle / 2, cycle: GlowPulse.musicCycle) - 1) < 1e-9)
    #expect(GlowPulse.level(at: 1.1) == GlowPulse.level(at: 1.1, cycle: GlowPulse.cycle))
}

@Test func playTimeIsFormatted() {
    #expect(MusicTime.format(0) == "0:00")
    #expect(MusicTime.format(65.9) == "1:05")
    #expect(MusicTime.format(3725) == "1:02:05")
    #expect(MusicTime.format(-3) == "0:00")
    // Echtes Minuszeichen wie bei Apple Music.
    #expect(MusicTime.remaining(position: 50, duration: 180) == "\u{2212}2:10")
}

@Test func sourceModesHaveGermanLabels() {
    #expect(MusicSourceMode.musicServices.label == "Nur Musikdienste")
    #expect(MusicSourceMode.allPlayers.label == "Alles, was abspielt")
}

@Test func newSourcesAreRemembered() {
    var settings = AppSettings.default
    let chrome = PlayerSource(bundleId: "com.google.Chrome", name: "Google Chrome")
    let added = settings.rememberMusicSources([spotify, chrome])
    #expect(added)
    #expect(settings.musicKnownSources == ["com.spotify.client": "Spotify", "com.google.Chrome": "Google Chrome"])
    // Nichts Neues (auch nicht bei anderem Namen): keine Änderung und damit kein Speichern.
    let again = settings.rememberMusicSources([PlayerSource(bundleId: "com.spotify.client", name: "spotify")])
    #expect(!again)
    #expect(settings.musicKnownSources["com.spotify.client"] == "Spotify")
}
