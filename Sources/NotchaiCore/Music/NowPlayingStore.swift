import Foundation

/// Führt die beiden Quellen zusammen (JXA-Abfrage und Benachrichtigungen von Spotify/Musik) und bestimmt,
/// was die Notch zeigt. Je App zählt die neueste Meldung; angezeigt wird nur, was `MusicFilter` durchlässt.
public struct NowPlayingStore: Sendable {
    /// So lange bleibt ein pausierter Titel sichtbar.
    public static let pausedLifetime: TimeInterval = 10 * 60
    /// So lange bleibt die eingeklappte Anzeige nach einer Pause stehen (kein Flackern beim Titelwechsel).
    public static let compactGrace: TimeInterval = 3
    /// Kleinere Abweichungen der gemeldeten Position vom Fortschreiben gelten als Messrauschen.
    public static let positionTolerance: TimeInterval = 1.5

    private struct Report: Sendable {
        var item: NowPlaying
        /// Seit wann pausiert (nicht bei jeder neuen „pausiert“-Meldung neu gesetzt).
        var pausedSince: Date?
        /// Die App meldet sich selbst (Spotify, Musik). Dann entscheidet die Abfrage nicht über ihr Verschwinden.
        var notifies: Bool
    }

    private var reports: [String: Report] = [:]
    private var seen: [String: PlayerSource] = [:]
    /// Die App, die die Abfrage zuletzt gemeldet hat.
    private var probeKey: String?

    public init() {}

    /// Ergebnis einer JXA-Abfrage; `nil` heißt „systemweit läuft nichts“.
    public mutating func apply(probe: NowPlaying?, now: Date) {
        guard let probe else {
            reports = reports.filter { $0.value.notifies }
            probeKey = nil
            return
        }
        let key = PlayerCatalog.canonical(probe.source).key
        if let old = probeKey, old != key, var report = reports[old], !report.notifies, report.item.isPlaying {
            // Die Abfrage kennt nur eine App. Wechselt sie, spielt die alte (soweit bekannt) nicht mehr.
            report.item.elapsed = report.item.position(at: now)
            report.item.timestamp = now
            report.item.isPlaying = false
            report.pausedSince = now
            reports[old] = report
        }
        probeKey = key
        merge(probe, notifies: false, now: now)
    }

    /// Benachrichtigung von Spotify oder Musik; ein leerer Titel heißt „gestoppt“.
    public mutating func apply(notification: NowPlaying, now: Date) {
        merge(notification, notifies: true, now: now)
    }

    /// Was die Notch zeigen soll: spielende vor pausierten, darunter die neueste Meldung.
    public func current(settings: AppSettings, now: Date) -> NowPlaying? {
        visible(settings: settings, now: now)?.item
    }

    /// Eingeklappte Anzeige: läuft gerade oder wurde vor höchstens `compactGrace` pausiert.
    public func showsCompact(settings: AppSettings, now: Date) -> Bool {
        guard settings.musicCompactView, let report = visible(settings: settings, now: now) else { return false }
        if report.item.isPlaying { return true }
        guard let pausedSince = report.pausedSince else { return false }
        return now.timeIntervalSince(pausedSince) <= Self.compactGrace
    }

    /// Alle bisher gesehenen Apps, nach Namen sortiert (für „Erkannte Player“).
    public var seenSources: [PlayerSource] {
        seen.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func visible(settings: AppSettings, now: Date) -> Report? {
        reports.values
            .filter { report in
                if let pausedSince = report.pausedSince, now.timeIntervalSince(pausedSince) > Self.pausedLifetime {
                    return false
                }
                return MusicFilter.accepts(report.item, settings: settings)
            }
            .max { a, b in
                if a.item.isPlaying != b.item.isPlaying { return b.item.isPlaying }
                return a.item.reportedAt < b.item.reportedAt
            }
    }

    private mutating func merge(_ incoming: NowPlaying, notifies: Bool, now: Date) {
        var item = incoming
        item.source = PlayerCatalog.canonical(incoming.source)
        let key = item.source.key
        let existing = reports[key]
        // Eine Abfrage, die vor der letzten Meldung gestartet ist, ist schon überholt.
        if let existing, item.reportedAt < existing.item.reportedAt { return }
        seen[key] = item.source
        let notifiesNow = notifies || (existing?.notifies ?? false)
        guard !item.title.isEmpty else {
            reports[key] = nil
            return
        }
        var pausedSince: Date? = nil
        if let existing, existing.item.title == item.title {
            // Fehlendes aus der vorigen Meldung derselben App und desselben Titels ergänzen.
            let old = existing.item
            item.artist = item.artist ?? old.artist
            item.album = item.album ?? old.album
            item.duration = item.duration ?? old.duration
            if item.elapsed == nil, let position = old.position(at: now) {
                item.elapsed = position
                item.timestamp = now
            } else if old.isPlaying, item.isPlaying, let reported = item.position(at: item.timestamp),
                      let projected = old.position(at: item.timestamp),
                      abs(reported - projected) < Self.positionTolerance {
                // Weiter fortschreiben statt springen: Der Fortschrittsbalken läuft dann gleichmäßig.
                item.elapsed = old.elapsed
                item.timestamp = old.timestamp
            }
            if !item.isPlaying { pausedSince = existing.pausedSince }
        }
        if !item.isPlaying, pausedSince == nil { pausedSince = now }
        reports[key] = Report(item: item, pausedSince: pausedSince, notifies: notifiesNow)
    }
}
