import Foundation

/// Übernahme von einer notchai-Installation (so hieß lumo bis 0.7.0): Einstellungen, Notizen und Ablage werden beim
/// ersten Start kopiert, die Hooks in Claude Code und Codex stellt `HookInstaller.migrateLegacy` auf `lumo-hook` um.
/// Der alte Ordner bleibt stehen; `brew uninstall --zap notchai` räumt ihn weg.
public enum LegacyMigration {
    public static let legacyName = "notchai"
    /// Hook-Einträge der alten App erkennt man an diesem Pfadstück.
    public static let legacyHookMarker = "/notchai/bin/notchai-hook"
    static let files = ["settings.json", "notes.json", "shelf.json"]

    public static func legacyAppSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support/\(legacyName)", directoryHint: .isDirectory)
    }

    /// Kopiert Einstellungen, Notizen und Ablage, soweit lumo noch keine eigenen hat.
    /// Gibt die Namen der kopierten Dateien zurück.
    @discardableResult
    public static func migrateFiles(home: URL) throws -> [String] {
        let fm = FileManager.default
        let old = legacyAppSupport(home: home)
        let new = LumoPaths.appSupport(home: home)
        var copied: [String] = []
        for name in files {
            let source = old.appending(path: name)
            let target = new.appending(path: name)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { continue }
            try fm.createDirectory(at: new, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            copied.append(name)
        }
        return copied
    }
}
