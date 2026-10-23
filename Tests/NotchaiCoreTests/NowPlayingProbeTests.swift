import Foundation
import Testing
@testable import NotchaiCore

private let now = Date(timeIntervalSince1970: 1_792_700_000)

private func parse(_ text: String) -> NowPlaying? {
    NowPlayingProbe.parse(Data(text.utf8), now: now)
}

@Test func probeReadsAllFields() throws {
    let np = try #require(parse(#"""
    {"title":"Blinding Lights","artist":"The Weeknd","album":"After Hours","duration":200.5,"position":42.25,"rate":1,"app":"Spotify","bundleId":"com.spotify.client"}
    """#))
    #expect(np.source == PlayerSource(bundleId: "com.spotify.client", name: "Spotify"))
    #expect(np.title == "Blinding Lights")
    #expect(np.artist == "The Weeknd")
    #expect(np.album == "After Hours")
    #expect(np.duration == 200.5)
    #expect(np.elapsed == 42.25)
    #expect(np.isPlaying)
    #expect(np.timestamp == now)
    #expect(np.reportedAt == now)
}

@Test func probePausedHasRateZero() throws {
    let np = try #require(parse(#"{"title":"Video","rate":0,"app":"Google Chrome"}"#))
    #expect(!np.isPlaying)
    #expect(np.artist == nil)
    #expect(np.duration == nil)
}

@Test func probeNullIsNothing() {
    #expect(parse("null\n") == nil)
    #expect(parse("") == nil)
    #expect(parse("   \n") == nil)
}

@Test func garbageProbeOutputIsNothing() {
    #expect(parse("execution error: Fehler (-1728)") == nil)
    #expect(parse(#"{"title":""}"#) == nil)
    #expect(parse(#"{"artist":"ohne Titel"}"#) == nil)
    #expect(parse("[1,2]") == nil)
}

@Test func probeWithoutBundleIdUsesName() throws {
    let np = try #require(parse(#"{"title":"x","app":"Google Chrome","bundleId":null,"rate":1}"#))
    #expect(np.source.key == "name:google chrome")
    let unnamed = try #require(parse(#"{"title":"x","rate":1}"#))
    #expect(unnamed.source.name == "Unbekannt")
}

@Test func zeroDurationMeansUnknown() throws {
    #expect(try #require(parse(#"{"title":"Livestream","duration":0,"rate":1,"app":"Safari"}"#)).duration == nil)
}

@Test func scriptReturnsJsonAsLastExpression() {
    let script = NowPlayingProbe.script
    #expect(script.contains("function run()"))
    #expect(script.contains("MRNowPlayingRequest"))
    #expect(script.contains("JSON.stringify"))
    // console.log landet auf stderr (`docs/now-playing.md`); das Ergebnis muss der Rückgabewert sein.
    #expect(!script.contains("console.log"))
}

// MARK: - Benachrichtigungen

@Test func spotifyNotificationIsParsed() throws {
    let np = try #require(PlayerNotification.parse(name: "com.spotify.client.PlaybackStateChanged", userInfo: [
        "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "Platte",
        "Duration": 215_000, "Playback Position": 12.5, "Track ID": "spotify:track:abc",
    ], now: now))
    #expect(np.source == PlayerSource(bundleId: "com.spotify.client", name: "Spotify"))
    #expect(np.title == "Song")
    #expect(np.duration == 215)
    #expect(np.elapsed == 12.5)
    #expect(np.isPlaying)
}

@Test func musicNotificationIsParsed() throws {
    let np = try #require(PlayerNotification.parse(name: "com.apple.Music.playerInfo", userInfo: [
        "Player State": "Paused", "Name": "Lied", "Artist": "Künstlerin", "Album": "Album", "Total Time": 180_500.0,
    ], now: now))
    #expect(np.source == PlayerSource(bundleId: "com.apple.Music", name: "Musik"))
    #expect(np.duration == 180.5)
    #expect(np.elapsed == nil)
    #expect(!np.isPlaying)
}

@Test func stoppedMeansGone() throws {
    let np = try #require(PlayerNotification.parse(name: "com.apple.Music.playerInfo",
                                                   userInfo: ["Player State": "Stopped"], now: now))
    #expect(np.title.isEmpty)
    #expect(!np.isPlaying)
}

@Test func unknownNotificationIsIgnored() {
    #expect(PlayerNotification.parse(name: "com.example.other", userInfo: ["Name": "x"], now: now) == nil)
    #expect(PlayerNotification.names == ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"])
}
