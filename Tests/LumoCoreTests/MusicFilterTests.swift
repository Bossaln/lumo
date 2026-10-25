import Foundation
import Testing
@testable import LumoCore

private let chrome = PlayerSource(bundleId: "com.google.Chrome", name: "Google Chrome")
private let music = PlayerSource(bundleId: "com.apple.Music", name: "Musik")
private let iina = PlayerSource(bundleId: "com.colliderli.iina", name: "IINA")
private let podcasts = PlayerSource(bundleId: "com.apple.podcasts", name: "Podcasts")

@Test func spotifyAndMusicAreServices() {
    #expect(PlayerCatalog.kind(of: spotify) == .musicService)
    #expect(PlayerCatalog.kind(of: music) == .musicService)
    #expect(PlayerCatalog.kind(of: PlayerSource(bundleId: "com.tidal.desktop", name: "TIDAL")) == .musicService)
    #expect(MusicFilter.accepts(track(source: spotify), settings: .default))
    #expect(MusicFilter.accepts(track(source: music, album: nil), settings: .default))
}

@Test func catalogKnowsTheOtherKinds() {
    #expect(PlayerCatalog.kind(of: chrome) == .browser)
    #expect(PlayerCatalog.kind(of: iina) == .video)
    #expect(PlayerCatalog.kind(of: podcasts) == .podcast)
    // Ohne Bundle-ID (JXA liefert evtl. nur den Namen) hilft der Anzeigename.
    #expect(PlayerCatalog.kind(of: PlayerSource(bundleId: nil, name: "Safari")) == .browser)
    #expect(PlayerCatalog.kind(of: PlayerSource(bundleId: nil, name: "Spotify")) == .musicService)
    #expect(PlayerCatalog.kind(of: PlayerSource(bundleId: nil, name: "Musik")) == .musicService)
}

@Test func unknownNameFallsBackToOther() {
    #expect(PlayerCatalog.kind(of: PlayerSource(bundleId: "com.example.Mystery", name: "Mystery")) == .other)
    #expect(!MusicFilter.accepts(track(source: PlayerSource(bundleId: "com.example.Mystery", name: "Mystery")), settings: .default))
}

@Test func browserVideoIsHiddenForMusicServices() {
    // YouTube-Video: Der Browser meldet Titel und Kanal, aber kein Album.
    #expect(AppSettings.default.musicSourceMode == .musicServices)
    #expect(!MusicFilter.accepts(track("Katzenvideo", source: chrome, album: nil), settings: .default))
    #expect(!MusicFilter.accepts(track("Katzenvideo", source: chrome, album: "  "), settings: .default))
    #expect(!MusicFilter.accepts(track(source: iina), settings: .default))
}

@Test func browserMusicWithAlbumIsShown() {
    // YouTube Music oder Spotify Web melden ein Album.
    #expect(MusicFilter.accepts(track(source: chrome, album: "Album"), settings: .default))
}

@Test func browserMusicCanBeSwitchedOff() {
    var settings = AppSettings.default
    settings.musicBrowserMusic = false
    #expect(!MusicFilter.accepts(track(source: chrome, album: "Album"), settings: settings))
}

@Test func allPlayersShowsEverything() {
    var settings = AppSettings.default
    settings.musicSourceMode = .allPlayers
    #expect(MusicFilter.accepts(track("Katzenvideo", source: chrome, album: nil), settings: settings))
    #expect(MusicFilter.accepts(track(source: iina), settings: settings))
    #expect(MusicFilter.accepts(track(source: PlayerSource(bundleId: nil, name: "Irgendwas")), settings: settings))
}

@Test func ruleNeverBeatsAllPlayers() {
    var settings = AppSettings.default
    settings.musicSourceMode = .allPlayers
    settings.musicSourceRules[chrome.key] = .never
    #expect(!MusicFilter.accepts(track(source: chrome), settings: settings))
    settings.musicSourceRules[spotify.key] = .never
    #expect(!MusicFilter.accepts(track(source: spotify), settings: settings))
}

@Test func ruleAlwaysBeatsMusicServices() {
    var settings = AppSettings.default
    settings.musicSourceRules[iina.key] = .always
    #expect(MusicFilter.accepts(track(source: iina), settings: settings))
    settings.musicSourceRules[iina.key] = .automatic
    #expect(!MusicFilter.accepts(track(source: iina), settings: settings))
}

@Test func podcastsFollowSetting() {
    var settings = AppSettings.default
    #expect(!MusicFilter.accepts(track(source: podcasts), settings: settings))
    settings.musicIncludePodcasts = true
    #expect(MusicFilter.accepts(track(source: podcasts), settings: settings))
}

@Test func musicDisabledShowsNothing() {
    var settings = AppSettings.default
    settings.musicEnabled = false
    #expect(!MusicFilter.accepts(track(source: spotify), settings: settings))
}

@Test func kindsHaveGermanLabels() {
    #expect(PlayerKind.musicService.label == "Musikdienst")
    #expect(PlayerKind.browser.label == "Browser")
    #expect(PlayerKind.other.label == "Sonstiges")
}

@Test func canonicalAddsBundleIdForKnownNames() {
    #expect(PlayerCatalog.canonical(PlayerSource(bundleId: nil, name: "Musik")).key == "com.apple.Music")
    #expect(PlayerCatalog.canonical(PlayerSource(bundleId: nil, name: "Spotify")).key == "com.spotify.client")
    // Eine vorhandene Bundle-ID und unbekannte Namen bleiben, wie sie sind.
    #expect(PlayerCatalog.canonical(PlayerSource(bundleId: "de.beispiel.player", name: "Spotify")).key == "de.beispiel.player")
    #expect(PlayerCatalog.canonical(PlayerSource(bundleId: nil, name: "Radio")).key == "name:radio")
}

@Test func automaticSummaryExplainsTheMode() {
    var settings = AppSettings.default
    #expect(MusicFilter.automaticSummary(for: .musicService, settings: settings) == "wird gezeigt")
    #expect(MusicFilter.automaticSummary(for: .browser, settings: settings) == "nur Musik (mit Album)")
    #expect(MusicFilter.automaticSummary(for: .video, settings: settings) == "wird nicht gezeigt")
    settings.musicBrowserMusic = false
    #expect(MusicFilter.automaticSummary(for: .browser, settings: settings) == "wird nicht gezeigt")
    settings.musicSourceMode = .allPlayers
    #expect(MusicFilter.automaticSummary(for: .video, settings: settings) == "wird gezeigt")
}
