import Foundation

/// Findet Programme an bekannten Orten. Aus der Menüleiste gestartete Apps kennen den `PATH` der
/// Shell nicht, deshalb wird nicht über `PATH` gesucht.
public enum ExecutableLocator {
    public static func find(_ name: String, candidates: [String], fileExists: (String) -> Bool) -> String? {
        candidates.first(where: fileExists)
    }

    public static func codexCandidates(home: URL) -> [String] {
        [home.appending(path: ".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    }

    public static let cmuxCandidates = ["/Applications/cmux.app/Contents/Resources/bin/cmux"]
}
