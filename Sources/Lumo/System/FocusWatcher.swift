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

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var known = false

    init(home: URL) {
        directory = home.appending(path: "Library/DoNotDisturb/DB", directoryHint: .isDirectory)
    }

    func start() {
        guard timer == nil else { return }
        read(initial: true)
        watchDirectory()
        timer = Timer.scheduledTimer(withTimeInterval: access == true ? 10 : 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(initial: false) }
        }
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

    private func read(initial: Bool) {
        let configurations: Data
        do {
            configurations = try Data(contentsOf: directory.appending(path: "ModeConfigurations.json"))
        } catch {
            if access != false { access = false }
            return
        }
        if access != true {
            access = true
            watchDirectory()
        }
        let assertions = try? Data(contentsOf: directory.appending(path: "Assertions.json"))
        guard let next = FocusModes.parse(configurations: configurations, assertions: assertions) else { return }
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
