import Foundation
import LumoCore

/// Beobachtet den Fokus über die Dateien, die macOS dafür führt (`~/Library/DoNotDisturb/DB`). Die Dateien sind
/// geschützt: Ohne vollen Festplattenzugriff für lumo bleibt `access` falsch, und lumo probiert es alle paar
/// Sekunden erneut, falls die Berechtigung inzwischen erteilt wurde.
@MainActor
final class FocusWatcher {
    /// Neuer Fokus (oder keiner) und der vorige.
    var onChange: ((FocusMode?, FocusMode?) -> Void)?
    private(set) var state: FocusModes?
    /// `nil`: noch nicht gelesen.
    private(set) var access: Bool?
    /// Letzter Lesefehler (Seite „System“ in den Einstellungen).
    private(set) var problem: String?

    private let directory: URL
    /// Kopie der zuletzt gelesenen Dateien unter ~/Library/Logs/lumo, falls lumo einen Fokus nicht erkennt.
    private let dumpURL: URL
    private var lastDump: Int?
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var known = false

    init(home: URL) {
        directory = home.appending(path: "Library/DoNotDisturb/DB", directoryHint: .isDirectory)
        dumpURL = home.appending(path: "Library/Logs/lumo/focus-files.txt")
    }

    func start() {
        guard timer == nil else { return }
        read(initial: true)
        watchDirectory()
        schedule()
    }

    /// Mit Zugriff alle drei Sekunden (falls die Ordner-Überwachung nichts meldet), ohne alle 15.
    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: access == true ? 3 : 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(initial: false) }
        }
    }

    /// Beide Dateien als Text, zum Kopieren (Seite „System“), falls lumo den Fokus nicht erkennt.
    func rawText() -> String {
        ["ModeConfigurations.json", "Assertions.json"].map { name in
            let text = (try? String(contentsOf: directory.appending(path: name), encoding: .utf8)) ?? L("(nicht lesbar)")
            return "=== \(name)\n\(text)"
        }.joined(separator: "\n\n")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
        known = false
    }

    /// Reagiert sofort, wenn macOS die Dateien ersetzt.
    private func watchDirectory() {
        guard source == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib],
                                                               queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read(initial: false) } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Schreibt beide Dateien ins Protokoll, wenn sie sich geändert haben.
    private func dump(configurations: Data, assertions: Data?) {
        let hash = configurations.hashValue ^ (assertions?.hashValue ?? 0)
        guard hash != lastDump else { return }
        lastDump = hash
        let text = "=== ModeConfigurations.json\n" + (String(data: configurations, encoding: .utf8) ?? "?")
            + "\n\n=== Assertions.json\n" + (assertions.flatMap { String(data: $0, encoding: .utf8) } ?? "(fehlt)") + "\n"
        try? FileManager.default.createDirectory(at: dumpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: dumpURL, atomically: true, encoding: .utf8)
    }

    private func read(initial: Bool) {
        let configurations: Data
        do {
            configurations = try Data(contentsOf: directory.appending(path: "ModeConfigurations.json"))
        } catch {
            problem = String(describing: error)
            if access != false {
                access = false
                schedule()
            }
            return
        }
        if access != true {
            access = true
            watchDirectory()
            schedule()
        }
        let assertions = try? Data(contentsOf: directory.appending(path: "Assertions.json"))
        dump(configurations: configurations, assertions: assertions)
        guard let next = FocusModes.parse(configurations: configurations, assertions: assertions) else {
            problem = L("ModeConfigurations.json ist kein lesbares JSON.")
            return
        }
        problem = nil
        let previous = state
        state = next
        guard known else {
            known = true
            return
        }
        guard !initial, previous?.activeIdentifier != next.activeIdentifier else { return }
        onChange?(next.activeMode, previous?.activeMode)
    }
}
