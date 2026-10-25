import Foundation
import Testing
@testable import LumoCore

@Test func defaultsMatchSpec() {
    let s = AppSettings.default
    #expect(s.signalStyle == .island)
    #expect(s.backgroundHex() == "#000000")
    #expect(s.claudeColorHex == "#E0764A")
    #expect(s.codexColorHex == "#8AA2FF")
    #expect(s.autoSendClaudeReplies == false)
    #expect(s.approvalTimeoutSeconds == 120)
    #expect(s.setupCompleted == false)
    #expect(s.checkForUpdates == true)
    #expect(s.panelOpenBehavior == .activity)
    #expect(s.musicArtworkBackground == true)
    #expect(s.musicCoverTransition == .blur)
    #expect(s.officeHotkey == true)
}

@Test func missingKeysFallBackToDefaults() throws {
    let json = #"{"signalStyle":"banner"}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(s.signalStyle == .banner)
    #expect(s.claudeColorHex == "#E0764A")
}

@Test func unknownEnumValueFallsBackToDefault() throws {
    let json = #"{"signalStyle":"hologram"}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(AppSettings.self, from: json)
    #expect(s.signalStyle == .island)
}

@Test func darkGrayHex() {
    var s = AppSettings.default
    s.background = .darkGray
    #expect(s.backgroundHex() == "#1C1C1E")
}

@Test func islandSideWidthRangeKeepsButtonsInside() {
    // ab 80 pt passen Punkt, Name und ✕/✓ in die Island.
    #expect(AppSettings.islandSideWidthRange.lowerBound == 80)
    #expect(AppSettings.islandSideWidthRange.contains(AppSettings.default.islandSideWidth))
}

@Test func decodedIslandSideWidthIsClampedToRange() throws {
    let narrow = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"islandSideWidth":30}"#.utf8))
    #expect(narrow.islandSideWidth == AppSettings.islandSideWidthRange.lowerBound)
    let wide = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"islandSideWidth":5000}"#.utf8))
    #expect(wide.islandSideWidth == AppSettings.islandSideWidthRange.upperBound)
    let normal = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"islandSideWidth":150}"#.utf8))
    #expect(normal.islandSideWidth == 150)
}

/// Jedes Feld anders als der Standard. Ein neues Feld in `AppSettings` muss hier eingetragen werden,
/// sonst schlägt `fixtureChangesEveryField` fehl; danach prüft der Roundtrip, ob es auch in
/// `CodingKeys` und `init(from:)` steht.
private func everyFieldChanged() -> AppSettings {
    var s = AppSettings()
    s.signalStyle = .vertical
    s.externalNotch = false
    s.externalNotchCenter = .music
    s.background = .custom
    s.customBackgroundHex = "#123456"
    s.claudeColorHex = "#AA0000"
    s.codexColorHex = "#00AA00"
    s.glowEnabled = false
    s.glowIntensity = 0.25
    s.soundsEnabled = false
    s.hoverDelayMs = 400
    s.watchClaude = false
    s.watchCodex = false
    s.signalOnQuestion = false
    s.signalOnPermission = false
    s.signalOnDone = false
    s.signalOnError = false
    s.approvalTimeoutSeconds = 60
    s.autoSendClaudeReplies = true
    s.sessionTitleSource = .sessionTitle
    s.sessionMaxAgeHours = 6
    s.musicEnabled = false
    s.musicCoverGlow = false
    s.musicCompactView = false
    s.officeEnabled = false
    s.officeScale = 1.5
    s.officeSound = true
    s.officeLighting = .fixedNight
    s.officeLatitude = 52.52
    s.officeLongitude = 13.405
    s.launchAtLogin = true
    s.islandSideWidth = 200
    s.setupCompleted = true
    s.checkForUpdates = false
    s.notchBounce = 0.9
    s.musicSourceMode = .allPlayers
    s.musicBrowserMusic = false
    s.musicIncludePodcasts = true
    s.musicLoadArtwork = false
    s.musicSourceRules = ["com.google.Chrome": .always]
    s.musicKnownSources = ["com.google.Chrome": "Google Chrome"]
    s.panelOpenBehavior = .lastUsed
    s.musicArtworkBackground = false
    s.musicCoverTransition = .flip
    s.officeHotkey = false
    s.developerOptions = true
    s.shelfEnabled = false
    s.language = .english
    s.musicTrackChangeStyle = .banner
    s.musicTrackChangeSeconds = 5
    s.musicVisualizer = .animated
    s.notesHotkey = false
    return s
}

@Test func fixtureChangesEveryField() {
    let changed = Mirror(reflecting: everyFieldChanged()).children
    let defaults = Mirror(reflecting: AppSettings.default).children
    #expect(changed.count == defaults.count)
    for (field, standard) in zip(changed, defaults) {
        #expect(String(describing: field.value) != String(describing: standard.value),
                "Feld \(field.label ?? "?") fehlt in everyFieldChanged()")
    }
}

@Test func everyFieldSurvivesSaveAndLoad() throws {
    let original = everyFieldChanged()
    let data = try JSONEncoder().encode(original)
    // Jedes gespeicherte Feld steht unter seinem Namen in der Datei (fehlt es in `CodingKeys`, fehlt es hier).
    let keys = Set(try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
    let fields = Set(Mirror(reflecting: original).children.compactMap(\.label))
    #expect(keys == fields)
    // Und `init(from:)` liest jedes davon zurück.
    #expect(try JSONDecoder().decode(AppSettings.self, from: data) == original)
}

@Test func wronglyTypedValuesFallBackToDefaults() throws {
    let json = #"""
    {"hoverDelayMs":"schnell","glowEnabled":"ja","claudeColorHex":42,"glowIntensity":[1],
     "signalStyle":7,"officeLatitude":"Nord","islandSideWidth":{"pt":200},"soundsEnabled":false}
    """#
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    let d = AppSettings.default
    #expect(s.hoverDelayMs == d.hoverDelayMs)
    #expect(s.glowEnabled == d.glowEnabled)
    #expect(s.claudeColorHex == d.claudeColorHex)
    #expect(s.glowIntensity == d.glowIntensity)
    #expect(s.signalStyle == d.signalStyle)
    #expect(s.officeLatitude == nil)
    #expect(s.islandSideWidth == d.islandSideWidth)
    // Ein falscher Wert verdirbt die übrigen nicht.
    #expect(s.soundsEnabled == false)
}

@Test func developerOptionsAreHiddenByDefault() {
    #expect(AppSettings.default.developerOptions == false)
}

@Test func languageFollowsTheMacUntilChosen() {
    var s = AppSettings()
    #expect(s.language == nil)
    #expect(s.resolvedLanguage(preferred: ["de-DE"]) == .german)
    #expect(s.resolvedLanguage(preferred: ["en-US"]) == .english)
    s.language = .english
    #expect(s.resolvedLanguage(preferred: ["de-DE"]) == .english)
}

@Test func unknownLanguageFallsBackToTheMac() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"language":"fr"}"#.utf8))
    #expect(s.language == nil)
}
