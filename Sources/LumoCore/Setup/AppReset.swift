import Foundation

/// Setzt lumo auf „gerade installiert“ zurück: Hooks aus Claude Code und Codex entfernen, danach alles
/// löschen, was lumo außerhalb des App-Bundles anlegt (Einstellungen, Hook-Programm, Sicherungen, Protokolle,
/// Caches, Fensterzustände). Die App selbst bleibt installiert.
public enum AppReset {
    /// Alle Orte, an denen lumo Daten ablegt.
    public static func dataLocations(home: URL, bundleID: String) -> [URL] {
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        return [
            LumoPaths.appSupport(home: home),
            library.appending(path: "Logs/lumo", directoryHint: .isDirectory),
            library.appending(path: "Caches/\(bundleID)", directoryHint: .isDirectory),
            library.appending(path: "HTTPStorages/\(bundleID)", directoryHint: .isDirectory),
            library.appending(path: "HTTPStorages/\(bundleID).binarycookies"),
            library.appending(path: "Saved Application State/\(bundleID).savedState", directoryHint: .isDirectory),
            library.appending(path: "Preferences/\(bundleID).plist"),
        ]
    }

    /// Entfernt erst die Hooks (fremde Einträge bleiben), dann jeden vorhandenen Ort über `remove`
    /// (die App legt sie in den Papierkorb). Fehlende Orte werden übersprungen.
    public static func perform(home: URL, bundleID: String, installer: HookInstaller,
                               remove: (URL) throws -> Void) throws {
        try installer.uninstallAll()
        for url in dataLocations(home: home, bundleID: bundleID)
        where FileManager.default.fileExists(atPath: url.path) {
            try remove(url)
        }
    }
}
