import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_700_000)

@Test func seekScriptsUseThePlayerPosition() {
    let spotify = MusicCommands.seekAppleScript(app: "Spotify", position: 83.5)
    #expect(spotify.hasPrefix("if application \"Spotify\" is running then"))
    #expect(spotify.contains("tell application \"Spotify\" to set player position to 83.50"))
    // Immer mit Punkt, egal welche Sprache der Mac hat.
    #expect(MusicCommands.seekAppleScript(app: "Music", position: 61.257).contains("to 61.26"))
    #expect(MusicCommands.seekAppleScript(app: "Music", position: -4).contains("to 0.00"))
}

@Test func seekJxaSetsElapsedTime() {
    let script = MusicCommands.seekJxa(position: 42)
    #expect(script.contains("MRMediaRemoteSetElapsedTime"))
    #expect(script.contains("(42.00)"))
}

@Test func scrubFractionMapsToPosition() {
    #expect(MusicScrub.position(fraction: 0.5, duration: 200) == 100)
    #expect(MusicScrub.position(fraction: -0.3, duration: 200) == 0)
    #expect(MusicScrub.position(fraction: 1.4, duration: 200) == 200)
    #expect(MusicScrub.position(fraction: 0.5, duration: 0) == 0)
}

@Test func seekOverrideRunsOnUntilThePlayerFollows() {
    let seek = MusicScrub.Override(position: 90, track: "a", playing: true, at: t0)
    #expect(seek.position(at: t0.addingTimeInterval(2)) == 92)
    #expect(MusicScrub.Override(position: 90, track: "a", playing: false, at: t0).position(at: t0.addingTimeInterval(2)) == 90)
    // Meldet der Player die neue Stelle, ist die Überbrückung erledigt.
    let followed = track(playing: true, elapsed: 91, at: t0.addingTimeInterval(1))
    #expect(seek.isSettled(by: followed, trackKey: "a", now: t0.addingTimeInterval(1)))
    // Noch die alte Stelle: weiter überbrücken.
    let stale = track(playing: true, elapsed: 30, at: t0.addingTimeInterval(1))
    #expect(!seek.isSettled(by: stale, trackKey: "a", now: t0.addingTimeInterval(1)))
    // Spätestens nach 3 s oder bei einem anderen Titel gilt wieder, was der Player meldet.
    #expect(seek.isSettled(by: stale, trackKey: "a", now: t0.addingTimeInterval(3.5)))
    #expect(seek.isSettled(by: stale, trackKey: "b", now: t0.addingTimeInterval(1)))
}
