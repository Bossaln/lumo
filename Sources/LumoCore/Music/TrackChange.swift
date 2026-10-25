import Foundation

/// Wie die Notch einen neuen Titel ankündigt.
public enum TrackChangeStyle: String, Codable, Equatable, Sendable, CaseIterable {
    /// Gar nicht; eingeklappt wechselt nur das Cover.
    case off
    /// Seitlich neben der Kamera: links das Cover, rechts Titel und Interpret.
    case island
    /// Unter der Kamera ausgefahren: großes Cover, Titel, Interpret.
    case banner

    /// Form der Notch während der Ankündigung; `nil` bei `off`.
    public var presentation: NotchPresentation? {
        switch self {
        case .off: nil
        case .island: .trackSides
        case .banner: .trackBanner
        }
    }
}

/// Woher die Balken ihre Höhe nehmen.
public enum MusicVisualizerMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Aus dem Ton, der gerade spielt (braucht die Freigabe „Systemaudio“, ab macOS 14.2).
    case audio
    /// Gleichmäßig animiert, ohne den Ton abzugreifen.
    case animated
}

/// Erkennt den Wechsel zum nächsten Titel. Angekündigt wird nur ein anderer Titel, der gerade spielt; der erste
/// Titel nach dem Start und ein Wechsel in der Pause nicht.
public struct TrackChangeDetector: Sendable {
    private var lastTrack: String?

    public init() {}

    /// Merkt sich `item` und meldet, ob es ein neuer, laufender Titel ist. `nil` (nichts läuft) vergisst nichts.
    public mutating func isNewTrack(_ item: NowPlaying?) -> Bool {
        guard let item else { return false }
        // Player und Titel genügen: Album und Interpret kommen bei Browsern oft einen Moment später.
        let key = item.source.key + "\u{1F}" + item.title
        defer { lastTrack = key }
        guard let lastTrack, lastTrack != key else { return false }
        return item.isPlaying
    }
}
