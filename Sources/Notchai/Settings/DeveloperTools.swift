import AppKit
import NotchaiCore
import ServiceManagement

/// Aktionen der Seite „Entwickler“ in den Einstellungen (eingeblendet über Einstellungen › Allgemein).
/// Die App füllt sie beim Start; die Seite selbst kennt weder Hooks noch Musik.
@MainActor
final class DeveloperTools {
    /// Hänger der App (Menüleiste, Notch); misst nur mit eingeschalteten Entwickleroptionen.
    let responsiveness: ResponsivenessMonitor
    var raiseSignal: (SignalContent) -> Void = { _ in }
    var closeSignal: () -> Void = {}
    /// Zeigt ein offenes Signal in der neu gewählten Form.
    var restyleSignal: () -> Void = {}
    var hookEventsText: () -> String = { "" }
    var nowPlayingText: () -> String = { "" }
    /// Begrüßung (Leuchten) und Einrichtung wie beim ersten Start.
    var showWelcome: () -> Void = {}
    /// Fragt nach und setzt notchai dann komplett zurück.
    var resetApp: () -> Void = {}

    init(responsiveness: ResponsivenessMonitor? = nil) {
        self.responsiveness = responsiveness ?? ResponsivenessMonitor()
    }

    static var logsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/notchai", directoryHint: .isDirectory)
    }

    static var dataFolder: URL {
        NotchaiPaths.appSupport(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func copy(_ text: String, empty: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? empty : text, forType: .string)
    }

    /// Öffnet einen Ordner im Finder (legt ihn an, falls es ihn noch nicht gibt).
    static func reveal(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}

/// Setzt notchai auf „gerade installiert“ zurück und startet neu (`AppReset`).
@MainActor
enum AppResetter {
    /// Fragt nach; `true`, wenn wirklich zurückgesetzt werden soll.
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "notchai komplett zurücksetzen?"
        alert.informativeText = """
            notchai entfernt seine Hooks aus Claude Code und Codex, legt Einstellungen, Sicherungen, \
            Protokolle und Caches in den Papierkorb und setzt seine Berechtigungen zurück. \
            Danach startet notchai neu, als wäre es gerade installiert.
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Zurücksetzen und neu starten")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func resetAndRelaunch(settingsStore: SettingsStore, stopServices: () -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bossaln.notchai"
        let installer = HookInstaller(home: home, hookBinaryPath: NotchaiPaths.hookBinary(home: home).path)
        stopServices()
        do {
            try AppReset.perform(home: home, bundleID: bundleID, installer: installer) { url in
                // Erst in den Papierkorb (lässt sich zurückholen), sonst endgültig löschen.
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Zurücksetzen nicht möglich"
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            _ = alert.runModal()
            return
        }
        // Ab hier darf nichts mehr gespeichert werden, sonst entstünden die Einstellungen beim Beenden neu.
        settingsStore.freeze()
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        run("/usr/bin/tccutil", ["reset", "All", bundleID], wait: true)
        // Neu starten, sobald diese Instanz beendet ist.
        run("/bin/sh", ["-c", "sleep 1; /usr/bin/open \(ShellQuote.quote(Bundle.main.bundlePath))"], wait: false)
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String], wait: Bool) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        if wait { process.waitUntilExit() }
    }
}
