/// Was die Notch zeigt: nur Musikdienste oder alles, was etwas abspielt.
public enum MusicSourceMode: String, Codable, Equatable, Sendable, CaseIterable {
    case musicServices, allPlayers

    public var label: String {
        switch self {
        case .musicServices: L("Nur Musikdienste")
        case .allPlayers: L("Alles, was abspielt")
        }
    }
}

/// Regel des Besitzers für eine einzelne App; sie geht dem Modus vor.
public enum MusicSourceRule: String, Codable, Equatable, Sendable, CaseIterable {
    case automatic, always, never
}

public enum MusicFilter {
    /// Darf `np` in der Notch erscheinen?
    /// - Regel der App (`always`/`never`) zuerst, dann der Modus.
    /// - „Nur Musikdienste“: Musikdienste immer; Browser nur mit Album (YouTube Music, Spotify Web melden eins,
    ///   YouTube-Videos nicht) und nur, wenn „Musik im Browser erkennen“ an ist; Podcasts nach Einstellung.
    public static func accepts(_ np: NowPlaying, settings: AppSettings) -> Bool {
        guard settings.musicEnabled else { return false }
        switch settings.musicSourceRules[np.source.key] ?? .automatic {
        case .always: return true
        case .never: return false
        case .automatic: break
        }
        guard settings.musicSourceMode == .musicServices else { return true }
        switch PlayerCatalog.kind(of: np.source) {
        case .musicService:
            return true
        case .browser:
            let hasAlbum = !(np.album ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return settings.musicBrowserMusic && hasAlbum
        case .podcast:
            return settings.musicIncludePodcasts
        case .video, .other:
            return false
        }
    }

    /// Was „Automatisch“ für eine App dieser Art gerade bedeutet (Liste „Erkannte Player“).
    public static func automaticSummary(for kind: PlayerKind, settings: AppSettings) -> String {
        let shown = L("wird gezeigt"), hidden = L("wird nicht gezeigt")
        guard settings.musicSourceMode == .musicServices else { return shown }
        switch kind {
        case .musicService: return shown
        case .browser: return settings.musicBrowserMusic ? L("nur Musik (mit Album)") : hidden
        case .podcast: return settings.musicIncludePodcasts ? shown : hidden
        case .video, .other: return hidden
        }
    }
}

public extension AppSettings {
    /// Trägt neu gesehene Player in „Erkannte Player“ ein; `true`, wenn sich etwas geändert hat.
    /// Bekannte bleiben unverändert, auch wenn eine Quelle sie anders nennt („Musik“/„Music“).
    @discardableResult
    mutating func rememberMusicSources(_ sources: [PlayerSource]) -> Bool {
        var changed = false
        for source in sources where musicKnownSources[source.key] == nil {
            musicKnownSources[source.key] = source.name
            changed = true
        }
        return changed
    }
}
