import Foundation
import LumoCore
import Observation

/// Misst, ob lumo sofort reagiert. Ein Hintergrund-Takt schickt zehnmal pro Sekunde eine winzige Aufgabe an
/// den Haupt-Thread und schaut, wie lange sie warten musste; dazu kommt die Zeit vom Klick auf das Menüleisten-
/// Symbol bis zum Öffnen des Menüs. Der Takt läuft nur mit eingeschalteten Entwickleroptionen.
@MainActor @Observable
final class ResponsivenessMonitor {
    private(set) var log = HangLog()
    /// Was gerade los ist (Notch, Musik, offene Fenster); steht bei jedem Hänger dabei.
    @ObservationIgnored var context: () -> String = { "" }
    @ObservationIgnored private var timer: DispatchSourceTimer?
    /// Benannte Arbeit, die zuletzt lange lief (`MainThreadWork`): Name, Dauer, Ende.
    @ObservationIgnored private var slowWork: [(name: String, milliseconds: Int, end: DispatchTime)] = []

    /// Misst nur mit eingeschalteten Entwickleroptionen.
    var isRunning: Bool { timer != nil }

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

    /// Benannte Arbeit auf dem Haupt-Thread ist fertig; was länger als 30 ms dauerte, kommt zum nächsten Hänger.
    func finished(_ name: String, nanoseconds: UInt64) {
        let milliseconds = Int(nanoseconds / 1_000_000)
        guard milliseconds >= 30 else { return }
        slowWork.append((name, milliseconds, .now()))
        if slowWork.count > 12 { slowWork.removeFirst(slowWork.count - 12) }
    }

    private func record(_ delay: TimeInterval, what: String?) {
        guard delay >= HangLog.threshold else { return }
        // Was in der Zeit des Hängers (plus etwas Spielraum) lange lief, steht mit in der Liste.
        let since = DispatchTime.now().uptimeNanoseconds &- UInt64((delay + 0.25) * 1_000_000_000)
        let suspects = slowWork.filter { $0.end.uptimeNanoseconds >= since }
            .map { "\($0.name) \($0.milliseconds) ms" }
        let slow = suspects.isEmpty ? nil : L("langsam: {0}", suspects.joined(separator: ", "))
        let context = [what, context(), slow].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        log.record(delay: delay, at: Date(), context: context)
    }
}

/// Es wartet immer höchstens eine Messung auf den Haupt-Thread.
private final class Probe: @unchecked Sendable {
    let queue = DispatchQueue(label: "lumo.responsiveness", qos: .utility)
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

/// Benannte Arbeit auf dem Haupt-Thread (Hooks, Musik, Zeichnen der Notch …). Mit eingeschalteten
/// Entwickleroptionen misst sie ihre Dauer für die Liste der Hänger; sonst kostet sie nichts.
@MainActor
enum MainThreadWork {
    static var monitor: ResponsivenessMonitor?

    @discardableResult
    static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        guard let monitor, monitor.isRunning else { return try work() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer { monitor.finished(name, nanoseconds: DispatchTime.now().uptimeNanoseconds - start) }
        return try work()
    }
}
