import Foundation

/// Alle Orte, an denen lumo außerhalb des App-Bundles etwas ablegt. `home` kommt immer von außen,
/// damit Tests auf einem Wegwerf-Home laufen.
public enum LumoPaths {
    public static func appSupport(home: URL) -> URL {
        home.appending(path: "Library/Application Support/lumo", directoryHint: .isDirectory)
    }

    /// Unix-Socket der App; `LUMO_SOCKET` überschreibt ihn (Tests).
    public static func socketPath(home: URL, env: [String: String]) -> String {
        if let override = env["LUMO_SOCKET"], !override.isEmpty { return override }
        return appSupport(home: home).appending(path: "lumo.sock").path
    }

    /// Fester Ort des Hook-Programms. Er ändert sich bei Updates nicht, sonst müsste der Besitzer
    /// die Hooks in Codex neu bestätigen (`docs/hooks.md`, Abschnitt 4).
    public static func hookBinary(home: URL) -> URL {
        appSupport(home: home).appending(path: "bin/lumo-hook")
    }

    public static func backupsDir(home: URL) -> URL {
        appSupport(home: home).appending(path: "backups", directoryHint: .isDirectory)
    }
}
