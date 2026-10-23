import Foundation

/// Alle Orte, an denen notchai außerhalb des App-Bundles etwas ablegt. `home` kommt immer von außen,
/// damit Tests auf einem Wegwerf-Home laufen.
public enum NotchaiPaths {
    public static func appSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support/notchai", directoryHint: .isDirectory)
    }

    /// Unix-Socket der App; `NOTCHAI_SOCKET` überschreibt ihn (Tests).
    public static func socketPath(home: URL, env: [String: String]) -> String {
        if let override = env["NOTCHAI_SOCKET"], !override.isEmpty { return override }
        return appSupport(home: home).appending(path: "notchai.sock").path
    }

    /// Fester Ort des Hook-Programms. Er ändert sich bei Updates nicht, sonst müsste der Besitzer
    /// die Hooks in Codex neu bestätigen (`docs/hooks.md`, Abschnitt 4).
    public static func hookBinary(home: URL) -> URL {
        appSupport(home: home).appending(path: "bin/notchai-hook")
    }

    public static func backupsDir(home: URL) -> URL {
        appSupport(home: home).appending(path: "backups", directoryHint: .isDirectory)
    }
}
