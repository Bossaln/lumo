import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_700_000)
private let chrome = PlayerSource(bundleId: "com.google.Chrome", name: "Google Chrome")
private let musicApp = PlayerSource(bundleId: "com.apple.Music", name: "Musik")

private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private var allPlayers: AppSettings {
    var s = AppSettings.default
    s.musicSourceMode = .allPlayers
    return s
}

@Test func newerReportOfSameAppWins() {
    var store = NowPlayingStore()
    store.apply(probe: track("Song", playing: true, at: at(0)), now: at(0))
    store.apply(notification: track("Song", playing: false, at: at(1)), now: at(1))
    #expect(store.current(settings: .default, now: at(1))?.isPlaying == false)
    // Eine ältere Meldung (Abfrage, die vor der Pause gestartet ist) überschreibt die Pause nicht.
    store.apply(probe: track("Song", playing: true, at: at(0.5)), now: at(0.5))
    #expect(store.current(settings: .default, now: at(2))?.isPlaying == false)
    store.apply(probe: track("Song", playing: true, at: at(3)), now: at(3))
    #expect(store.current(settings: .default, now: at(3))?.isPlaying == true)
}

@Test func playingBeatsPaused() {
    var store = NowPlayingStore()
    store.apply(probe: track("Video", source: chrome, album: nil, playing: true, at: at(0)), now: at(0))
    store.apply(notification: track("Song", playing: false, at: at(5)), now: at(5))
    #expect(store.current(settings: allPlayers, now: at(5))?.title == "Video")
}

@Test func filteredSourceIsSkipped() {
    // YouTube-Video läuft im Browser, Spotify ist pausiert: Bei „Nur Musikdienste“ bleibt Spotify sichtbar.
    var store = NowPlayingStore()
    store.apply(notification: track("Song", playing: false, at: at(0)), now: at(0))
    store.apply(probe: track("Katzenvideo", source: chrome, album: nil, playing: true, at: at(1)), now: at(1))
    #expect(store.current(settings: .default, now: at(1))?.title == "Song")
    #expect(store.showsCompact(settings: .default, now: at(10)) == false)
}

@Test func probeNilClearsOnlyItsSource() {
    var store = NowPlayingStore()
    store.apply(notification: track("Song", playing: true, at: at(0)), now: at(0))
    store.apply(probe: track("Video", source: chrome, album: nil, playing: true, at: at(1)), now: at(1))
    store.apply(probe: nil, now: at(2))
    #expect(store.current(settings: allPlayers, now: at(2))?.title == "Song")
}

@Test func probeSwitchingAppsPausesTheOldProbeReport() {
    // Die Abfrage kennt nur eine App. Wechselt sie, läuft die alte nicht „ewig weiter“.
    var store = NowPlayingStore()
    store.apply(probe: track("Video", source: chrome, album: nil, playing: true, at: at(0)), now: at(0))
    store.apply(probe: track("Song", playing: false, at: at(1)), now: at(1))
    let current = store.current(settings: allPlayers, now: at(2))
    #expect(current?.title == "Song")
}

@Test func probeSwitchKeepsAppsWithOwnNotifications() {
    // Spotify meldet sich selbst; dass die Abfrage zu Chrome wechselt, ändert an Spotify nichts.
    var store = NowPlayingStore()
    store.apply(notification: track("Song", playing: true, at: at(0)), now: at(0))
    store.apply(probe: track("Song", playing: true, at: at(1)), now: at(1))
    store.apply(probe: track("Katzenvideo", source: chrome, album: nil, playing: true, at: at(2)), now: at(2))
    store.apply(probe: nil, now: at(3))
    #expect(store.current(settings: .default, now: at(3))?.isPlaying == true)
}

@Test func probeWithoutBundleIdMergesWithNotification() throws {
    // Musik meldet Dauer, aber keine Position; die Abfrage (nur mit App-Namen) liefert die Position.
    var store = NowPlayingStore()
    store.apply(notification: track("Lied", source: musicApp, playing: true, elapsed: nil, duration: 180, at: at(0)), now: at(0))
    store.apply(probe: track("Lied", source: PlayerSource(bundleId: nil, name: "Musik"), playing: true, elapsed: 20,
                             duration: nil, at: at(1)), now: at(1))
    let current = try #require(store.current(settings: .default, now: at(1)))
    #expect(current.source.key == "com.apple.Music")
    #expect(current.duration == 180)
    #expect(current.elapsed == 20)
    #expect(store.seenSources.map(\.key) == ["com.apple.Music"])
}

@Test func notificationKeepsPositionFromProbe() throws {
    var store = NowPlayingStore()
    store.apply(probe: track("Lied", source: musicApp, playing: true, elapsed: 20, duration: 180, at: at(0)), now: at(0))
    store.apply(notification: track("Lied", source: musicApp, playing: false, elapsed: nil, duration: 180, at: at(10)), now: at(10))
    let current = try #require(store.current(settings: .default, now: at(10)))
    #expect(current.isPlaying == false)
    #expect(current.position(at: at(60)) == 30)
}

@Test func pausedDisappearsAfterTenMinutes() {
    var store = NowPlayingStore()
    store.apply(notification: track(playing: false, at: at(0)), now: at(0))
    // Die Abfrage meldet weiter „pausiert“; das verlängert die Frist nicht.
    store.apply(probe: track(playing: false, at: at(300)), now: at(300))
    #expect(store.current(settings: .default, now: at(9 * 60)) != nil)
    #expect(store.current(settings: .default, now: at(11 * 60)) == nil)
}

@Test func compactSurvivesShortPause() {
    var store = NowPlayingStore()
    store.apply(notification: track("A", playing: true, at: at(0)), now: at(0))
    #expect(store.showsCompact(settings: .default, now: at(0)))
    store.apply(notification: track("A", playing: false, at: at(1)), now: at(1))
    #expect(store.showsCompact(settings: .default, now: at(2)))
    #expect(!store.showsCompact(settings: .default, now: at(5)))
}

@Test func stoppedRemovesSource() {
    var store = NowPlayingStore()
    store.apply(notification: track("A", playing: true, at: at(0)), now: at(0))
    store.apply(notification: track("", playing: false, at: at(1)), now: at(1))
    #expect(store.current(settings: .default, now: at(1)) == nil)
}

@Test func seenSourcesAreCollected() {
    var store = NowPlayingStore()
    store.apply(notification: track(at: at(0)), now: at(0))
    store.apply(probe: track(source: chrome, at: at(1)), now: at(1))
    #expect(store.seenSources.map(\.name) == ["Google Chrome", "Spotify"])
}

@Test func smallPositionDriftIsSmoothedOut() throws {
    // Jede Abfrage misst die Position etwas anders; kleine Abweichungen ließen den Balken zittern.
    var store = NowPlayingStore()
    store.apply(probe: track(playing: true, elapsed: 30, at: at(0)), now: at(0))
    store.apply(probe: track(playing: true, elapsed: 32.4, at: at(2)), now: at(2))
    #expect(try #require(store.current(settings: .default, now: at(2))).position(at: at(2)) == 32)
    // Ein echter Sprung (Spulen) wird übernommen.
    store.apply(probe: track(playing: true, elapsed: 90, at: at(4)), now: at(4))
    #expect(try #require(store.current(settings: .default, now: at(4))).position(at: at(4)) == 90)
    // Beim Pausieren zählt die gemeldete Position genau.
    store.apply(probe: track(playing: false, elapsed: 91.2, at: at(5)), now: at(5))
    #expect(try #require(store.current(settings: .default, now: at(9))).position(at: at(9)) == 91.2)
}
