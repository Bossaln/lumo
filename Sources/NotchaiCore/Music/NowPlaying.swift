import Foundation

/// Die App, die gerade etwas abspielt.
public struct PlayerSource: Hashable, Codable, Sendable {
    public var bundleId: String?
    /// Anzeigename, etwa „Spotify“ oder „Google Chrome“.
    public var name: String

    public init(bundleId: String?, name: String) {
        self.bundleId = bundleId
        self.name = name
    }

    /// Fester Schlüssel für Einstellungen: die Bundle-ID, ohne sie der Name.
    public var key: String {
        if let bundleId, !bundleId.isEmpty { return bundleId }
        return "name:" + name.lowercased()
    }
}

/// Was gerade läuft (oder zuletzt lief), aus einer der Quellen (`NowPlayingProbe`, `PlayerNotification`).
public struct NowPlaying: Equatable, Sendable {
    public var source: PlayerSource
    public var title: String
    public var artist: String?
    public var album: String?
    /// Länge in Sekunden.
    public var duration: TimeInterval?
    /// Position in Sekunden zum Zeitpunkt `timestamp`.
    public var elapsed: TimeInterval?
    public var timestamp: Date
    public var isPlaying: Bool
    /// Wann diese Meldung eintraf (für „die neuere gewinnt“).
    public var reportedAt: Date

    public init(source: PlayerSource, title: String, artist: String?, album: String?, duration: TimeInterval?,
                elapsed: TimeInterval?, timestamp: Date, isPlaying: Bool, reportedAt: Date) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.reportedAt = reportedAt
    }

    /// Position zum Zeitpunkt `now`: läuft weiter, solange gespielt wird, begrenzt auf 0…Dauer.
    public func position(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        let running = isPlaying ? max(0, now.timeIntervalSince(timestamp)) : 0
        let position = max(0, elapsed + running)
        guard let duration, duration > 0 else { return position }
        return min(position, duration)
    }

    /// Erkennt denselben Titel über Meldungen hinweg (Cover-Zwischenspeicher, Zusammenführen).
    public var trackKey: String {
        [source.key, title, artist ?? "", album ?? ""].joined(separator: "\u{1F}")
    }
}
