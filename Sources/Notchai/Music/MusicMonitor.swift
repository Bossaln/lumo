import AppKit
import NotchaiCore

/// Hält fest, was gerade läuft, und schreibt es ins `AppModel`:
/// - Spotify und Musik melden sich selbst (`DistributedNotificationCenter`), ohne Abfrage.
/// - Alle anderen Player fragt eine JXA-Abfrage über Apples `osascript` ab (`NowPlayingProbe`).
/// - Lädt Cover und Leuchtfarbe und schickt Befehle.
/// Alles Langsame läuft in eigenen Prozessen mit Frist; die Notch wartet nie darauf.
@MainActor
final class MusicMonitor {
    private static let osascript = "/usr/bin/osascript"
    private static let tick: TimeInterval = 1
    /// Abstand der Abfragen: im offenen Reiter „Musik“, wenn etwas läuft, und wenn gar nichts läuft.
    private static let probeIntervalTabOpen: TimeInterval = 1
    private static let probeIntervalActive: TimeInterval = 2
    private static let probeIntervalIdle: TimeInterval = 4
    private static let probeTimeout: TimeInterval = 3
    private static let scriptTimeout: TimeInterval = 2
    /// So viele Fehlschläge in Folge, bis die Abfrage als „nichts läuft“ gilt.
    private static let failuresUntilEmpty = 3
    private static let artworkCacheSize = 8
    /// So lange bleibt beim Titelwechsel das alte Cover stehen, während das neue lädt.
    private static let artworkWait: TimeInterval = 1.5
    /// Kantenlänge der Bitmap, aus der die Leuchtfarbe berechnet wird.
    private static let glowSampleSize = 24

    private let model: AppModel
    private var store = NowPlayingStore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Eine Abfrage läuft; es startet nie eine zweite.
    private var probing = false
    private var lastProbeStart = Date.distantPast
    private var lastProbeFoundSomething = false
    private var probeFailures = 0
    /// Titel (`trackKey`), dessen Cover gerade lädt; bis dahin bleibt das alte stehen.
    private var pendingTrack: String?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkOrder: [String] = []

    // Prüfhilfe für `docs/now-playing.md` (Entwickler-Menü).
    private var lastProbeOutput = "–"
    private var lastProbeDetails = "noch keine Abfrage"
    private var recentNotifications: [String] = []

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard timer == nil else { return }
        let center = DistributedNotificationCenter.default()
        for name in PlayerNotification.names {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                var info: [String: Any] = [:]
                for (key, value) in note.userInfo ?? [:] {
                    if let key = key as? String { info[key] = value }
                }
                MainActor.assumeIsolated { self?.received(name: name, userInfo: info) }
            })
        }
        model.onMusicCommand = { [weak self] command in self?.send(command) }
        model.onMusicSeek = { [weak self] position in self?.seek(to: position) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickFired() }
        }
        tickFired()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers = []
    }

    // MARK: - Quellen

    private func tickFired() {
        let settings = model.settingsStore.settings
        if settings.musicEnabled, !probing {
            let interval = model.musicTabOpen ? Self.probeIntervalTabOpen
                : lastProbeFoundSomething ? Self.probeIntervalActive : Self.probeIntervalIdle
            if Date().timeIntervalSince(lastProbeStart) >= interval - 0.05 { probe() }
        }
        // Auch ohne neue Meldung: Pausiertes läuft ab, die eingeklappte Anzeige endet nach der Pause.
        publish()
    }

    private func probe() {
        probing = true
        let started = Date()
        lastProbeStart = started
        Task { [weak self] in
            // stderr verwerfen: Warnungen von osascript würden das JSON verderben.
            let result = await ProcessRunner.run(Self.osascript, ["-l", "JavaScript", "-e", NowPlayingProbe.script],
                                                 timeout: Self.probeTimeout, includeErrors: false)
            self?.probeFinished(result, started: started)
        }
    }

    private func probeFinished(_ result: CommandResult, started: Date) {
        probing = false
        let now = Date()
        let millis = Int(now.timeIntervalSince(started) * 1000)
        lastProbeOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        lastProbeDetails = "Status \(result.status), \(millis) ms, \(started.formatted(date: .omitted, time: .standard))"
        if result.status == 0 {
            probeFailures = 0
            // Zeitpunkt der Meldung ist der Start: Eine Benachrichtigung, die währenddessen kam, ist neuer.
            let item = NowPlayingProbe.parse(Data(result.output.utf8), now: started)
            lastProbeFoundSomething = item != nil
            store.apply(probe: item, now: now)
        } else {
            // Zeitüberschreitung oder Fehler: ein Ausrutscher ändert nichts, mehrere heißen „nichts läuft“.
            probeFailures += 1
            if probeFailures == Self.failuresUntilEmpty {
                lastProbeFoundSomething = false
                store.apply(probe: nil, now: now)
            }
        }
        publish()
    }

    private func received(name: String, userInfo: [String: Any]) {
        let now = Date()
        let fields = userInfo.keys.sorted().map { "\($0)=\(userInfo[$0] ?? "")" }.joined(separator: ", ")
        recentNotifications.append("\(now.formatted(date: .omitted, time: .standard)) \(name): \(fields)")
        if recentNotifications.count > 8 { recentNotifications.removeFirst() }
        guard model.settingsStore.settings.musicEnabled,
              let item = PlayerNotification.parse(name: name, userInfo: userInfo, now: now) else { return }
        store.apply(notification: item, now: now)
        publish()
    }

    /// Überträgt den Stand ins Modell; gesetzt wird nur, was sich geändert hat (kein unnötiges Neuzeichnen).
    private func publish() {
        let settings = model.settingsStore.settings
        let now = Date()
        let current = settings.musicEnabled ? store.current(settings: settings, now: now) : nil
        let compact = settings.musicEnabled && store.showsCompact(settings: settings, now: now)
        if model.nowPlaying != current { model.nowPlaying = current }
        if let seek = model.musicSeek, seek.isSettled(by: current, trackKey: current?.trackKey, now: now) {
            model.musicSeek = nil
        }
        // Der Player hat den neuen Zustand gemeldet: Die sofortige Rückmeldung des Knopfs ist erledigt.
        if let override = model.musicPlayingOverride, current?.isPlaying == override || current == nil {
            model.musicPlayingOverride = nil
        }
        if model.showsCompactMusic != compact { model.showsCompactMusic = compact }
        let sources = store.seenSources
        if sources.contains(where: { settings.musicKnownSources[$0.key] == nil }) {
            model.settingsStore.settings.rememberMusicSources(sources)
        }
        updateArtwork(for: current, loadArtwork: settings.musicLoadArtwork)
    }

    // MARK: - Cover

    private func updateArtwork(for item: NowPlaying?, loadArtwork: Bool) {
        guard let item else {
            pendingTrack = nil
            if model.artworkTrack != nil { showArtwork(nil, icon: nil, track: nil) }
            return
        }
        let track = item.trackKey
        guard track != model.artworkTrack, track != pendingTrack else { return }
        let icon = Self.appIcon(for: item.source)
        if let cached = artworkCache[track] {
            showArtwork(cached, icon: icon, track: track)
            return
        }
        guard loadArtwork, let app = MusicCommands.appleScriptApp(for: item.source),
              let script = MusicCommands.artworkScript(app: app), Self.isRunning(item.source) else {
            showArtwork(nil, icon: icon, track: track)
            return
        }
        // Das alte Cover bleibt kurz stehen, damit beim Umklappen gleich das neue erscheint.
        pendingTrack = track
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.artworkWait))
            guard let self, pendingTrack == track else { return }
            pendingTrack = nil
            showArtwork(nil, icon: icon, track: track)
        }
        Task { [weak self] in
            let result = await ProcessRunner.run(Self.osascript, ["-e", script], timeout: Self.scriptTimeout,
                                                 includeErrors: false)
            let image = result.status == 0 ? await Self.image(fromScriptOutput: result.output) : nil
            self?.artworkLoaded(image, icon: icon, track: track)
        }
    }

    private func artworkLoaded(_ image: NSImage?, icon: NSImage?, track: String) {
        if let image {
            artworkCache[track] = image
            artworkOrder.removeAll { $0 == track }
            artworkOrder.append(track)
            while artworkOrder.count > Self.artworkCacheSize {
                artworkCache[artworkOrder.removeFirst()] = nil
            }
        }
        // Inzwischen läuft vielleicht schon der nächste Titel.
        if pendingTrack == track {
            pendingTrack = nil
            showArtwork(image, icon: icon, track: track)
        } else if model.artworkTrack == track, let image {
            // Kam nach Ablauf der Wartezeit: Symbol durch das Cover ersetzen.
            showArtwork(image, icon: icon, track: track)
        }
    }

    private func showArtwork(_ image: NSImage?, icon: NSImage?, track: String?) {
        let apply = { [weak self] in
            guard let model = self?.model else { return }
            model.artworkTrack = track
            model.artwork = image
            model.musicAppIcon = icon
            model.artworkGlow = image.flatMap(Self.glowColor)
        }
        // Ein neuer Titel nach einem anderen: erst die Richtung setzen, dann (im nächsten Durchlauf) das Cover
        // wechseln. SwiftUI nimmt das Wegklappen des alten Covers aus dessen letztem Stand.
        guard model.artworkTrack != nil, track != nil, track != model.artworkTrack else {
            apply()
            return
        }
        let last = model.lastMusicCommand
        let direction = SkipDirection.forTrackChange(lastCommand: last?.command, sentAt: last?.at, now: Date())
        guard model.skipDirection != direction else {
            apply()
            return
        }
        model.skipDirection = direction
        Task { @MainActor in apply() }
    }

    /// Musik liefert die Bilddaten (`«data …»`), Spotify eine Bild-URL auf seinem Bildserver.
    private static func image(fromScriptOutput output: String) async -> NSImage? {
        if let data = AppleScriptData.parse(output) { return NSImage(data: data) }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 5)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    /// Cover auf eine kleine Bitmap verkleinern und daraus die Leuchtfarbe berechnen.
    private static func glowColor(_ image: NSImage) -> RGB? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let size = glowSampleSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return drawn ? ArtworkColor.glow(rgba: pixels, width: size, height: size) : nil
    }

    private static func appIcon(for source: PlayerSource) -> NSImage? {
        guard let id = PlayerCatalog.canonical(source).bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// AppleScript spricht eine App nur an, wenn sie schon läuft; notchai startet nie Spotify oder Musik.
    private static func isRunning(_ source: PlayerSource) -> Bool {
        guard let id = PlayerCatalog.canonical(source).bundleId else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    // MARK: - Befehle

    private func send(_ command: MusicCommand) {
        guard let source = model.nowPlaying?.source else { return }
        Task { [weak self] in
            if let app = MusicCommands.appleScriptApp(for: source), Self.isRunning(source) {
                _ = await ProcessRunner.run(Self.osascript, ["-e", MusicCommands.appleScript(command, app: app)],
                                            timeout: Self.scriptTimeout)
            } else {
                _ = await ProcessRunner.run(Self.osascript, ["-l", "JavaScript", "-e", MusicCommands.jxa(command)],
                                            timeout: Self.probeTimeout)
            }
            // Gleich neu abfragen, damit Play/Pause und Titel sofort stimmen.
            guard let self else { return }
            lastProbeStart = .distantPast
            tickFired()
        }
    }

    /// Spulen: Spotify und Musik per AppleScript, alle anderen über MediaRemote (JXA).
    private func seek(to position: TimeInterval) {
        guard let source = model.nowPlaying?.source else { return }
        Task { [weak self] in
            if let app = MusicCommands.appleScriptApp(for: source), Self.isRunning(source) {
                _ = await ProcessRunner.run(Self.osascript, ["-e", MusicCommands.seekAppleScript(app: app, position: position)],
                                            timeout: Self.scriptTimeout)
            } else {
                _ = await ProcessRunner.run(Self.osascript, ["-l", "JavaScript", "-e", MusicCommands.seekJxa(position: position)],
                                            timeout: Self.probeTimeout)
            }
            guard let self else { return }
            lastProbeStart = .distantPast
            tickFired()
        }
    }

    // MARK: - Prüfhilfe

    /// Letzte JXA-Ausgabe und Benachrichtigungen samt aller Schlüssel (Entwickler-Menü).
    func rawDataText() -> String {
        let shown = model.nowPlaying.map { "\($0.title) – \($0.source.name) (\($0.source.key)), spielt: \($0.isPlaying)" }
        return """
        JXA-Abfrage (\(lastProbeDetails)):
        \(lastProbeOutput.isEmpty ? "(leer)" : lastProbeOutput)

        Benachrichtigungen (Spotify, Musik):
        \(recentNotifications.isEmpty ? "(noch keine)" : recentNotifications.joined(separator: "\n"))

        Angezeigt: \(shown ?? "nichts")
        Erkannte Player: \(store.seenSources.map { "\($0.name) [\($0.key)] – \(PlayerCatalog.kind(of: $0).label)" }.joined(separator: "; "))
        """
    }
}
