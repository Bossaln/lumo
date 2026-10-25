import Foundation
import LumoCore
import Observation

/// Echte Balken: greift den Ton ab, solange Balken zu sehen sind und Musik spielt, und rechnet beim Zeichnen
/// die Höhen aus (`VisualizerBars`). Liefert `nil`, solange kein echter Ton ankommt; die Balken tanzen dann
/// wie bisher von selbst. Nichts davon wird gespeichert oder verschickt.
@MainActor @Observable
final class MusicVisualizer {
    enum Status: Equatable {
        /// Aus, weil keine Balken zu sehen sind (oder animierte Balken gewählt sind).
        case idle
        /// macOS älter als 14.2: keine Core-Audio-Taps.
        case unsupported
        case starting
        case running
        /// Läuft, aber es kommt nur Stille an: Vermutlich fehlt die Freigabe „Systemaudio“.
        case silent
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// Höhen der Balken und ihre Spitzen (je 0…1).
    struct Spectrum {
        let levels: [Double]
        let peaks: [Double]
    }

    private struct BarsKey: Hashable {
        let count: Int
        let leveling: VisualizerBars.Leveling
    }

    static let fftSize = 1024
    /// So lange darf nach dem Start nur Stille kommen, bis lumo eine fehlende Freigabe vermutet.
    private static let silenceUntilHint: TimeInterval = 5

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let ring = AudioSampleRing(capacity: 8192)
    /// Anlegen und Abbauen des Taps dauert; es passiert nie auf dem Hauptthread.
    @ObservationIgnored private let control = DispatchQueue(label: "com.bossaln.lumo.visualizer", qos: .userInitiated)
    @ObservationIgnored private var tap: AnyObject?
    /// Player, dessen Ton gerade abgegriffen wird (`nil` = alles); `.none`, solange nichts läuft.
    @ObservationIgnored private var tappedBundle: String??
    /// Jeder Start und jedes Stoppen zählt hoch; späte Rückmeldungen eines alten Starts verfallen.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sampleRate = 48_000.0
    @ObservationIgnored private var analyzer = SpectrumAnalyzer(size: MusicVisualizer.fftSize)
    @ObservationIgnored private var samples = [Float](repeating: 0, count: MusicVisualizer.fftSize)
    @ObservationIgnored private var bars: [BarsKey: VisualizerBars] = [:]
    @ObservationIgnored private var lastFrame: [BarsKey: (time: TimeInterval, spectrum: Spectrum)] = [:]
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var lastFrameCount = 0
    @ObservationIgnored private var stalledChecks = 0

    /// Beobachtet, ob Balken zu sehen sind, und startet bzw. stoppt den Abgriff.
    func start(model: AppModel) {
        self.model = model
        observe()
    }

    private func observe() {
        guard let model else { return }
        let wanted: String?? = withObservationTracking {
            let settings = model.settingsStore.settings
            let active = settings.musicEnabled && settings.musicVisualizer == .audio && model.showsMusicBars
            return active ? .some(model.nowPlaying.flatMap { PlayerCatalog.canonical($0.source).bundleId }) : nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        update(wanted: wanted)
    }

    /// `wanted`: `nil` = aus, sonst der Player (innen `nil` = unbekannt, dann alles).
    private func update(wanted: String??) {
        guard let bundle = wanted else {
            stop()
            return
        }
        guard tappedBundle != .some(bundle) else { return }
        guard #available(macOS 14.2, *) else {
            status = .unsupported
            return
        }
        let tap = (self.tap as? SystemAudioTap) ?? SystemAudioTap(ring: ring)
        self.tap = tap
        tappedBundle = .some(bundle)
        generation += 1
        let generation = generation
        status = .starting
        // Direkt einreihen, nicht über einen Task: Start und Stopp müssen in der Reihenfolge der Aufrufe laufen.
        control.async {
            let result = Result<Double, Error> {
                try tap.start(bundleId: bundle)
                return tap.sampleRate
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.started(result, generation: generation) }
            }
        }
    }

    private func started(_ result: Result<Double, Error>, generation: Int) {
        guard generation == self.generation else { return }
        switch result {
        case .success(let rate):
            sampleRate = rate
            bars = [:]
            lastFrame = [:]
            status = .running
            startedAt = Date()
            lastFrameCount = 0
            stalledChecks = 0
            watchdog?.invalidate()
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        case .failure(let error):
            watchdog?.invalidate()
            watchdog = nil
            status = .failed(String(describing: error))
            // Nicht gleich wieder versuchen; erst, wenn die Balken das nächste Mal erscheinen.
        }
    }

    private func stop() {
        watchdog?.invalidate()
        watchdog = nil
        guard tappedBundle != nil else { return }
        tappedBundle = nil
        generation += 1
        if status != .unsupported { status = .idle }
        if let tap = tap {
            control.async {
                if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.stop() }
            }
        }
    }

    /// Jede Sekunde: Kommt noch Ton? Nach einem Wechsel der Ausgabe (AirPods …) bleibt der Tap stumm und wird neu
    /// gestartet. Kommt nach dem Start nur Stille, fehlt vermutlich die Freigabe.
    private func check() {
        let frames = ring.framesWritten
        stalledChecks = frames == lastFrameCount ? stalledChecks + 1 : 0
        lastFrameCount = frames
        if stalledChecks >= 2, let bundle = tappedBundle {
            tappedBundle = nil
            update(wanted: .some(bundle))
            return
        }
        let heard = ring.hasHeardSound
        if !heard, status == .running, Date().timeIntervalSince(startedAt) > Self.silenceUntilHint {
            status = .silent
        } else if heard, status == .silent {
            status = .running
        }
    }

    /// Höhen von `count` Balken (0…1) für das Bild zur Zeit `time`; `nil` ohne echten Ton.
    func levels(count: Int, at time: TimeInterval) -> [Double]? {
        spectrum(count: count, leveling: .perBand, at: time)?.levels
    }

    /// Höhen und Spitzen von `count` Balken für das Bild zur Zeit `time`; `nil` ohne echten Ton.
    /// Zeichnen zwei Ansichten im selben Bild dieselben Balken, rechnet lumo nur einmal.
    func spectrum(count: Int, leveling: VisualizerBars.Leveling, at time: TimeInterval) -> Spectrum? {
        guard status == .running, ring.hasHeardSound else { return nil }
        let key = BarsKey(count: count, leveling: leveling)
        if let last = lastFrame[key], last.time == time { return last.spectrum }
        guard ring.copyLatest(into: &samples) else { return nil }
        let magnitudes = analyzer.magnitudes(of: samples)
        var bands = bars[key] ?? VisualizerBars(count: count, sampleRate: sampleRate, fftSize: Self.fftSize,
                                                leveling: leveling)
        // Nach einer Pause im Zeichnen nicht mit einem riesigen Schritt weitermachen.
        let dt = lastFrame[key].map { min(max(time - $0.time, 0), 0.1) } ?? 1.0 / 60
        bands.update(magnitudes: magnitudes, dt: dt)
        bars[key] = bands
        let spectrum = Spectrum(levels: bands.levels, peaks: bands.peaks)
        lastFrame[key] = (time, spectrum)
        return spectrum
    }
}
