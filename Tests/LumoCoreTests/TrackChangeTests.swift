import CoreGraphics
import Foundation
import Testing
@testable import LumoCore

// MARK: - Erkennen

/// Spielt die Meldungen der Reihe nach ab und gibt zurück, welche als neuer Titel galten.
private func announced(_ items: [NowPlaying?]) -> [Bool] {
    var detector = TrackChangeDetector()
    return items.map { detector.isNewTrack($0) }
}

@Test func firstTrackIsNotAnnounced() {
    // Beim Start von lumo oder beim ersten Abspielen fährt nichts aus.
    #expect(announced([track("Eins")]) == [false])
}

@Test func nextTrackIsAnnounced() {
    #expect(announced([track("Eins"), track("Eins"), track("Zwei"), track("Zwei")]) == [false, false, true, false])
}

@Test func pausedTrackChangeIsNotAnnounced() {
    // Spielt der in der Pause gewählte Titel dann los, ist es kein neuer Titel mehr.
    #expect(announced([track("Eins"), track("Zwei", playing: false), track("Zwei")]) == [false, false, false])
}

@Test func stoppingAndRestartingWithAnotherTrackIsAnnounced() {
    #expect(announced([track("Eins"), nil, track("Zwei")]) == [false, false, true])
}

@Test func lateAlbumOrArtistIsNoNewTrack() {
    // Browser melden Album und Interpret oft erst einen Moment nach dem Titel.
    #expect(announced([track("Eins", album: nil), track("Eins", album: "Album")]) == [false, false])
}

@Test func otherPlayerWithNewTrackIsAnnounced() {
    let chrome = PlayerSource(bundleId: "com.google.Chrome", name: "Google Chrome")
    #expect(announced([track("Eins"), track("Zwei", source: chrome)]) == [false, true])
}

// MARK: - Form

@Test func trackSidesShowCoverLeftAndTitleRight() {
    let f = NotchGeometry.frame(for: .trackSides, screen: air, islandSideWidth: 80)!
    #expect(f.width == 188 + 2 * NotchGeometry.trackSideWidth)
    #expect(f.height == 32); #expect(f.midX == 756); #expect(f.maxY == 982)
    // Breiter als die eingeklappte Musik, aus der sie ausfährt.
    #expect(f.width > NotchGeometry.frame(for: .compact, screen: air, islandSideWidth: 80)!.width)
}

@Test func trackBannerDropsBelowTheCamera() {
    let f = NotchGeometry.frame(for: .trackBanner, screen: air, islandSideWidth: 120)!
    #expect(f.width == NotchGeometry.trackBannerWidth)
    #expect(f.height == 32 + NotchGeometry.trackBannerExtraHeight)
    #expect(f.midX == 756); #expect(f.maxY == 982)
}

@Test func styleChoosesThePresentation() {
    #expect(TrackChangeStyle.off.presentation == nil)
    #expect(TrackChangeStyle.island.presentation == .trackSides)
    #expect(TrackChangeStyle.banner.presentation == .trackBanner)
}

// MARK: - Einstellungen

@Test func trackChangeDefaults() {
    let s = AppSettings.default
    #expect(s.musicTrackChangeStyle == .island)
    #expect(s.musicTrackChangeSeconds == 3)
    #expect(s.musicVisualizer == .audio)
}

@Test func trackChangeSecondsAreClamped() throws {
    let short = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"musicTrackChangeSeconds":0.2}"#.utf8))
    #expect(short.musicTrackChangeSeconds == AppSettings.trackChangeSecondsRange.lowerBound)
    let long = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"musicTrackChangeSeconds":60}"#.utf8))
    #expect(long.musicTrackChangeSeconds == AppSettings.trackChangeSecondsRange.upperBound)
    #expect(AppSettings.trackChangeSecondChoices.allSatisfy(AppSettings.trackChangeSecondsRange.contains))
    #expect(AppSettings.trackChangeSecondChoices.contains(2))
    #expect(AppSettings.trackChangeSecondChoices.contains(3))
}
