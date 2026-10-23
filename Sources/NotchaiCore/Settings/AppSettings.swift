import Foundation

public enum SignalStyle: String, Codable, Equatable, Sendable { case vertical, island, banner }
public enum SessionViewStyle: String, Codable, Equatable, Sendable { case list, circles }
public enum BackgroundStyle: String, Codable, Equatable, Sendable { case black, darkGray, custom }
public enum SessionTitleSource: String, Codable, Equatable, Sendable { case lastPrompt, sessionTitle }
public enum OfficeLighting: String, Codable, Equatable, Sendable { case realSun, fixedDay, fixedNight }
/// Wie das Cover beim Titelwechsel wechselt: weich überblenden oder in Skip-Richtung umklappen.
public enum CoverTransitionStyle: String, Codable, Equatable, Sendable, CaseIterable { case blur, flip }

/// Alle Einstellungen von notchai. Fehlende oder unlesbare Schlüssel fallen beim Dekodieren auf die Standardwerte zurück.
/// Ein neues Feld gehört an vier Stellen: Eigenschaft, `CodingKeys`, `init(from:)` und `everyFieldChanged()`
/// in `AppSettingsTests` (deren Roundtrip-Test meldet jede vergessene Stelle).
public struct AppSettings: Codable, Equatable, Sendable {
    public var signalStyle: SignalStyle = .island
    public var sessionViewStyle: SessionViewStyle = .list
    public var background: BackgroundStyle = .black
    public var customBackgroundHex: String = "#000000"
    public var claudeColorHex: String = "#E0764A"
    public var codexColorHex: String = "#8AA2FF"
    public var glowEnabled: Bool = true
    public var glowIntensity: Double = 0.6
    public var soundsEnabled: Bool = true
    public var hoverDelayMs: Int = 150
    public var watchClaude: Bool = true
    public var watchCodex: Bool = true
    public var signalOnQuestion: Bool = true
    public var signalOnPermission: Bool = true
    public var signalOnDone: Bool = true
    public var signalOnError: Bool = true
    /// Auf 5…125 begrenzt (Hook-Timeout ist 130 s).
    public var approvalTimeoutSeconds: Int = 120
    public var autoSendClaudeReplies: Bool = false
    public var sessionTitleSource: SessionTitleSource = .lastPrompt
    public var sessionMaxAgeHours: Int = 24
    public var musicEnabled: Bool = true
    public var musicCoverGlow: Bool = true
    public var musicCompactView: Bool = true
    public var officeEnabled: Bool = true
    public var officeScale: Double = 1.0
    public var officeSound: Bool = false
    public var officeLighting: OfficeLighting = .realSun
    public var officeLatitude: Double? = nil
    public var officeLongitude: Double? = nil
    public var launchAtLogin: Bool = false
    public var islandSideWidth: Double = 120
    /// Der Einrichtungs-Assistent wurde einmal durchlaufen.
    public var setupCompleted: Bool = false
    /// Beim Start und alle sechs Stunden per Git nachsehen, ob es einen neuen Stand gibt.
    public var checkForUpdates: Bool = true
    /// Gummi-Effekt beim Auf- und Zuklappen: 0 = aus, 1 = kräftig (`NotchSpring`).
    public var notchBounce: Double = 0.4
    /// Was die Musikanzeige zeigt: nur Musikdienste oder alles, was abspielt (`MusicFilter`).
    public var musicSourceMode: MusicSourceMode = .musicServices
    /// Bei „Nur Musikdienste“: Musik im Browser (YouTube Music, Spotify Web …) erkennen.
    public var musicBrowserMusic: Bool = true
    public var musicIncludePodcasts: Bool = false
    /// Cover per AppleScript holen (Spotify-Cover kommen von Spotifys Bildserver).
    public var musicLoadArtwork: Bool = true
    /// Regel je App (Schlüssel `PlayerSource.key`); fehlt sie, gilt `automatic`.
    public var musicSourceRules: [String: MusicSourceRule] = [:]
    /// Bisher gesehene Player (Schlüssel → Anzeigename) für die Liste in den Einstellungen.
    public var musicKnownSources: [String: String] = [:]
    /// Welcher Reiter beim Aufklappen erscheint (`PanelTabChoice`).
    public var panelOpenBehavior: PanelOpenBehavior = .activity
    /// Hintergrund des Reiters „Musik“ verschwommen in den Farben des Covers statt schwarz.
    public var musicArtworkBackground: Bool = true
    public var musicCoverTransition: CoverTransitionStyle = .blur
    /// Zweimal rechte ⌘ öffnet das große Büro.
    public var officeHotkey: Bool = true
    /// Blendet in den Einstellungen die Seite „Entwickler“ ein (Test-Signale, Rohdaten, Zurücksetzen).
    public var developerOptions: Bool = false

    public static let `default` = AppSettings()

    /// Erlaubte Breite je Island-Seite in pt. Ab 80 passen Punkt, Agentname und ✕/✓ neben die Kamera.
    public static let islandSideWidthRange: ClosedRange<Double> = 80...320

    public init() {}

    /// Hintergrundfarbe als Hex-Text je nach gewähltem Stil.
    public func backgroundHex() -> String {
        switch background {
        case .black: "#000000"
        case .darkGray: "#1C1C1E"
        case .custom: customBackgroundHex
        }
    }

    private enum CodingKeys: String, CodingKey {
        case signalStyle, sessionViewStyle, background, customBackgroundHex, claudeColorHex, codexColorHex
        case glowEnabled, glowIntensity, soundsEnabled, hoverDelayMs, watchClaude, watchCodex
        case signalOnQuestion, signalOnPermission, signalOnDone, signalOnError
        case approvalTimeoutSeconds, autoSendClaudeReplies, sessionTitleSource, sessionMaxAgeHours
        case musicEnabled, musicCoverGlow, musicCompactView
        case officeEnabled, officeScale, officeSound, officeLighting, officeLatitude, officeLongitude
        case launchAtLogin, islandSideWidth, setupCompleted, checkForUpdates, notchBounce
        case musicSourceMode, musicBrowserMusic, musicIncludePodcasts, musicLoadArtwork, musicSourceRules, musicKnownSources
        case panelOpenBehavior, musicArtworkBackground, musicCoverTransition, officeHotkey, developerOptions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ target: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { target = v }
        }
        // Enums über den Rohwert lesen: unbekannte Werte behalten den Standard.
        func option<T: RawRepresentable>(_ key: CodingKeys, _ target: inout T) where T.RawValue == String {
            if let raw = try? c.decodeIfPresent(String.self, forKey: key), let v = T(rawValue: raw) { target = v }
        }
        option(.signalStyle, &s.signalStyle)
        option(.sessionViewStyle, &s.sessionViewStyle)
        option(.background, &s.background)
        value(.customBackgroundHex, &s.customBackgroundHex)
        value(.claudeColorHex, &s.claudeColorHex)
        value(.codexColorHex, &s.codexColorHex)
        value(.glowEnabled, &s.glowEnabled)
        value(.glowIntensity, &s.glowIntensity)
        value(.soundsEnabled, &s.soundsEnabled)
        value(.hoverDelayMs, &s.hoverDelayMs)
        value(.watchClaude, &s.watchClaude)
        value(.watchCodex, &s.watchCodex)
        value(.signalOnQuestion, &s.signalOnQuestion)
        value(.signalOnPermission, &s.signalOnPermission)
        value(.signalOnDone, &s.signalOnDone)
        value(.signalOnError, &s.signalOnError)
        value(.approvalTimeoutSeconds, &s.approvalTimeoutSeconds)
        value(.autoSendClaudeReplies, &s.autoSendClaudeReplies)
        option(.sessionTitleSource, &s.sessionTitleSource)
        value(.sessionMaxAgeHours, &s.sessionMaxAgeHours)
        value(.musicEnabled, &s.musicEnabled)
        value(.musicCoverGlow, &s.musicCoverGlow)
        value(.musicCompactView, &s.musicCompactView)
        value(.officeEnabled, &s.officeEnabled)
        value(.officeScale, &s.officeScale)
        value(.officeSound, &s.officeSound)
        option(.officeLighting, &s.officeLighting)
        s.officeLatitude = (try? c.decodeIfPresent(Double.self, forKey: .officeLatitude)) ?? nil
        s.officeLongitude = (try? c.decodeIfPresent(Double.self, forKey: .officeLongitude)) ?? nil
        value(.launchAtLogin, &s.launchAtLogin)
        value(.islandSideWidth, &s.islandSideWidth)
        value(.setupCompleted, &s.setupCompleted)
        value(.checkForUpdates, &s.checkForUpdates)
        value(.notchBounce, &s.notchBounce)
        s.notchBounce = min(max(s.notchBounce, 0), 1)
        option(.musicSourceMode, &s.musicSourceMode)
        value(.musicBrowserMusic, &s.musicBrowserMusic)
        value(.musicIncludePodcasts, &s.musicIncludePodcasts)
        value(.musicLoadArtwork, &s.musicLoadArtwork)
        // Unbekannte Regeln einzeln überspringen, statt die ganze Liste zu verlieren.
        if let rules = try? c.decodeIfPresent([String: String].self, forKey: .musicSourceRules) {
            s.musicSourceRules = rules.compactMapValues(MusicSourceRule.init(rawValue:))
        }
        value(.musicKnownSources, &s.musicKnownSources)
        option(.panelOpenBehavior, &s.panelOpenBehavior)
        value(.musicArtworkBackground, &s.musicArtworkBackground)
        option(.musicCoverTransition, &s.musicCoverTransition)
        value(.officeHotkey, &s.officeHotkey)
        value(.developerOptions, &s.developerOptions)
        let range = Self.islandSideWidthRange
        s.islandSideWidth = min(max(s.islandSideWidth, range.lowerBound), range.upperBound)
        self = s
    }
}
