import Foundation
import Testing
@testable import NotchaiCore

private let t0 = Date(timeIntervalSince1970: 1_792_700_000)
let spotify = PlayerSource(bundleId: "com.spotify.client", name: "Spotify")

func track(_ title: String = "Song", source: PlayerSource = spotify, album: String? = "Album", playing: Bool = true,
           elapsed: TimeInterval? = 30, duration: TimeInterval? = 200, at time: Date = t0) -> NowPlaying {
    NowPlaying(source: source, title: title, artist: "Band", album: album, duration: duration, elapsed: elapsed,
               timestamp: time, isPlaying: playing, reportedAt: time)
}

@Test func positionAdvancesWhilePlaying() {
    #expect(track().position(at: t0.addingTimeInterval(12)) == 42)
}

@Test func positionStandsStillWhenPaused() {
    #expect(track(playing: false).position(at: t0.addingTimeInterval(12)) == 30)
}

@Test func positionIsClampedToDuration() {
    #expect(track().position(at: t0.addingTimeInterval(500)) == 200)
    #expect(track(elapsed: -4).position(at: t0) == 0)
    #expect(track(elapsed: nil).position(at: t0) == nil)
    // Ohne Dauer läuft die Position einfach weiter.
    #expect(track(duration: nil).position(at: t0.addingTimeInterval(500)) == 530)
}

@Test func sourceKeyPrefersBundleId() {
    #expect(spotify.key == "com.spotify.client")
    #expect(PlayerSource(bundleId: nil, name: "Google Chrome").key == "name:google chrome")
    #expect(PlayerSource(bundleId: "", name: "Arc").key == "name:arc")
}

@Test func trackKeyChangesWithTheSong() {
    #expect(track("A").trackKey != track("B").trackKey)
    #expect(track("A").trackKey == track("A", elapsed: 99).trackKey)
}
