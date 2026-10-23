/// Art einer abspielenden App; entscheidet, was „Nur Musikdienste“ durchlässt.
public enum PlayerKind: String, Sendable, CaseIterable {
    case musicService, browser, video, podcast, other

    public var label: String {
        switch self {
        case .musicService: "Musikdienst"
        case .browser: "Browser"
        case .video: "Video"
        case .podcast: "Podcast"
        case .other: "Sonstiges"
        }
    }
}

/// Bekannte Apps nach Art, über die Bundle-ID oder, wenn die fehlt, über den Anzeigenamen.
/// Unbekannte Apps sind „Sonstiges“; der Besitzer kann jede App einzeln auf „immer“ stellen.
public enum PlayerCatalog {
    private static let bundleIds: [String: PlayerKind] = [
        // Musikdienste und Musik-Player
        "com.spotify.client": .musicService, "com.apple.Music": .musicService, "com.apple.iTunes": .musicService,
        "com.tidal.desktop": .musicService, "com.deezer.deezer-desktop": .musicService, "com.amazon.music": .musicService,
        "com.qobuz.QobuzDesktop": .musicService, "com.github.th-ch.youtube-music": .musicService,
        "tv.plex.plexamp": .musicService, "co.brushedtype.doppler-macos": .musicService,
        "com.swinsian.Swinsian": .musicService, "com.coppertino.Vox": .musicService, "org.cogx.cog": .musicService,
        "com.pandora.desktop": .musicService, "sh.cider.electron": .musicService, "com.soundcloud.desktop": .musicService,
        // Browser
        "com.apple.Safari": .browser, "com.apple.SafariTechnologyPreview": .browser, "com.google.Chrome": .browser,
        "com.google.Chrome.canary": .browser, "org.mozilla.firefox": .browser, "com.microsoft.edgemac": .browser,
        "company.thebrowser.Browser": .browser, "company.thebrowser.dia": .browser, "com.brave.Browser": .browser,
        "com.operasoftware.Opera": .browser, "com.vivaldi.Vivaldi": .browser, "com.kagi.kagimacOS": .browser,
        "app.zen-browser.zen": .browser, "org.chromium.Chromium": .browser,
        // Video
        "com.colliderli.iina": .video, "org.videolan.vlc": .video, "com.apple.QuickTimePlayerX": .video,
        "com.apple.TV": .video, "com.firecore.infuse": .video, "io.mpv": .video,
        // Podcasts
        "com.apple.podcasts": .podcast, "fm.overcast.overcast": .podcast, "au.com.shiftyjelly.PocketCasts": .podcast,
    ]

    /// Anzeigenamen in Kleinbuchstaben (deutsch und englisch).
    private static let names: [String: PlayerKind] = [
        "spotify": .musicService, "musik": .musicService, "music": .musicService, "itunes": .musicService,
        "tidal": .musicService, "deezer": .musicService, "amazon music": .musicService, "qobuz": .musicService,
        "youtube music": .musicService, "plexamp": .musicService, "doppler": .musicService, "swinsian": .musicService,
        "vox": .musicService, "cog": .musicService, "pandora": .musicService, "cider": .musicService,
        "soundcloud": .musicService,
        "safari": .browser, "safari technology preview": .browser, "google chrome": .browser, "chrome": .browser,
        "firefox": .browser, "microsoft edge": .browser, "arc": .browser, "dia": .browser, "brave browser": .browser,
        "brave": .browser, "opera": .browser, "vivaldi": .browser, "orion": .browser, "zen": .browser,
        "zen browser": .browser, "chromium": .browser,
        "iina": .video, "vlc": .video, "quicktime player": .video, "tv": .video, "infuse": .video, "mpv": .video,
        "podcasts": .podcast, "overcast": .podcast, "pocket casts": .podcast,
    ]

    /// Eindeutige Anzeigenamen → Bundle-ID, damit eine Abfrage ohne Bundle-ID dieselbe Quelle trifft
    /// wie die Benachrichtigung (und dieselbe Regel in den Einstellungen).
    private static let idsByName: [String: String] = [
        "spotify": "com.spotify.client", "musik": "com.apple.Music", "music": "com.apple.Music",
        "safari": "com.apple.Safari", "google chrome": "com.google.Chrome", "firefox": "org.mozilla.firefox",
        "microsoft edge": "com.microsoft.edgemac", "arc": "company.thebrowser.Browser", "brave browser": "com.brave.Browser",
        "podcasts": "com.apple.podcasts", "quicktime player": "com.apple.QuickTimePlayerX", "iina": "com.colliderli.iina",
        "vlc": "org.videolan.vlc",
    ]

    public static func kind(of source: PlayerSource) -> PlayerKind {
        if let id = source.bundleId, let kind = bundleIds[id] { return kind }
        return names[source.name.lowercased()] ?? .other
    }

    /// Ergänzt die Bundle-ID über den Namen, wenn sie fehlt und der Name eindeutig ist.
    public static func canonical(_ source: PlayerSource) -> PlayerSource {
        if let id = source.bundleId, !id.isEmpty { return source }
        guard let id = idsByName[source.name.lowercased()] else { return source }
        return PlayerSource(bundleId: id, name: source.name)
    }
}
