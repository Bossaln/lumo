import Foundation
import Testing
@testable import LumoCore

@Test func spotifyAndMusicUseAppleScript() {
    #expect(MusicCommands.appleScriptApp(for: spotify) == "Spotify")
    #expect(MusicCommands.appleScriptApp(for: PlayerSource(bundleId: "com.apple.Music", name: "Musik")) == "Music")
    // Die Abfrage liefert manchmal nur den Namen.
    #expect(MusicCommands.appleScriptApp(for: PlayerSource(bundleId: nil, name: "Musik")) == "Music")
}

@Test func othersUseJxa() {
    #expect(MusicCommands.appleScriptApp(for: PlayerSource(bundleId: "com.google.Chrome", name: "Google Chrome")) == nil)
    #expect(MusicCommands.appleScriptApp(for: PlayerSource(bundleId: nil, name: "IINA")) == nil)
    let script = MusicCommands.jxa(.playPause)
    #expect(script.contains("MRNowPlayingController"))
    #expect(script.contains("localRouteController"))
}

@Test func commandNumbersMatchMediaRemote() {
    #expect(MusicCommand.playPause.mediaRemoteNumber == 2)
    #expect(MusicCommand.next.mediaRemoteNumber == 4)
    #expect(MusicCommand.previous.mediaRemoteNumber == 5)
    #expect(MusicCommands.jxa(.next).contains("sendCommandOptionsCompletion(4,"))
    #expect(MusicCommands.jxa(.previous).contains("sendCommandOptionsCompletion(5,"))
}

@Test func appleScriptVerbs() {
    #expect(MusicCommands.appleScript(.playPause, app: "Spotify").contains("tell application \"Spotify\" to playpause"))
    #expect(MusicCommands.appleScript(.next, app: "Music").contains("tell application \"Music\" to next track"))
    #expect(MusicCommands.appleScript(.previous, app: "Music").contains("tell application \"Music\" to previous track"))
}

@Test func scriptsCheckThatTheAppRuns() {
    // lumo startet nie Spotify oder Musik: Jedes Skript fragt zuerst, ob die App läuft.
    for command in MusicCommand.allCases {
        #expect(MusicCommands.appleScript(command, app: "Spotify").hasPrefix("if application \"Spotify\" is running then"))
    }
    let spotifyArtwork = MusicCommands.artworkScript(app: "Spotify")
    #expect(spotifyArtwork?.hasPrefix("if application \"Spotify\" is running then") == true)
    #expect(spotifyArtwork?.contains("artwork url of current track") == true)
    let musicArtwork = MusicCommands.artworkScript(app: "Music")
    #expect(musicArtwork?.hasPrefix("if application \"Music\" is running then") == true)
    #expect(musicArtwork?.contains("data of artwork 1 of current track") == true)
    #expect(MusicCommands.artworkScript(app: "Safari") == nil)
}
