import Foundation
import NotchaiCore
import Observation

/// Misst, ob notchai sofort reagiert. Ein Hintergrund-Takt schickt zehnmal pro Sekunde eine winzige Aufgabe an
/// den Haupt-Thread und schaut, wie lange sie warten musste; dazu kommt die Zeit vom Klick auf das Menüleisten-
/// Symbol bis zum Öffnen des Menüs. Der Takt läuft nur mit eingeschalteten Entwickleroptionen.
@MainActor @Observable
final class ResponsivenessMonitor {
    private(set) var log = HangLog()
    /// Was gerade los ist (Notch, Musik, offene Fenster); steht bei jedem Hänger dabei.
    @ObservationIgnored var context: () -> String = { "" }
    @ObservationIgnored private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let probe = Probe()
        let timer = DispatchSource.makeTimerSource(queue: probe.queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            // Höchstens eine Messung wartet; hängt der Haupt-Thread, zählt sie die ganze Zeit.
            guard probe.begin() else { return }
            let sent = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                let delay = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1_000_000_000
                probe.end()
                MainActor.assumeIsolated { self?.record(delay, what: nil) }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Das Menü in der Menüleiste öffnete erst `delay` Sekunden nach dem Klick.
    func menuOpened(after delay: TimeInterval) {
        record(delay, what: L("Menüleiste: Menü nach dem Klick"))
    }

    private func record(_ delay: TimeInterval, what: String?) {
        guard delay >= HangLog.threshold else { return }
        let context = [what, context()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        log.record(delay: delay, at: Date(), context: context)
    }
}

/// Es wartet immer höchstens eine Messung auf den Haupt-Thread.
private final class Probe: @unchecked Sendable {
    let queue = DispatchQueue(label: "notchai.responsiveness", qos: .utility)
    private let lock = NSLock()
    private var waiting = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !waiting else { return false }
        waiting = true
        return true
    }

    func end() {
        lock.lock()
        waiting = false
        lock.unlock()
    }
}
