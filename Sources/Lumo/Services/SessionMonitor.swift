import Foundation
import LumoCore

/// Liest alle 1,5 s die Transkripte laufender Sessions nach (`TranscriptLibrary`) und meldet geänderte
/// Zusammenfassungen samt Tagesbilanz. Gelesen wird auf einer eigenen Warteschlange, gemeldet auf dem Main-Thread.
@MainActor
final class SessionMonitor {
    private static let interval: TimeInterval = 1.5

    /// Gehört allein `queue`.
    private let library: TranscriptLibrary
    private let queue = DispatchQueue(label: "lumo.transcripts", qos: .utility)
    private let maxAgeHours: () -> Int
    private let onUpdate: ([TranscriptSummary], DailyStats) -> Void
    private var timer: Timer?
    /// Ein Durchlauf läuft noch; der nächste Takt wird dann ausgelassen.
    private var polling = false

    init(home: URL, maxAgeHours: @escaping () -> Int, onUpdate: @escaping ([TranscriptSummary], DailyStats) -> Void) {
        library = TranscriptLibrary(home: home)
        self.maxAgeHours = maxAgeHours
        self.onUpdate = onUpdate
    }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        let library = library
        let hours = maxAgeHours()
        queue.async { [weak self] in
            let now = Date()
            let changed = library.poll(now: now, maxAgeHours: hours, calendar: .current)
            let stats = DailyStatsCalculator.compute(library.summaries, day: now, calendar: .current, now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.polling = false
                    self.onUpdate(changed, stats)
                }
            }
        }
    }
}
