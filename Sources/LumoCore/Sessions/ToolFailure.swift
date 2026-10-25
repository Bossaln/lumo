import Foundation

/// Fehlgeschlagene Werkzeugaufrufe für den Fehlerzähler. Lehnt der Besitzer eine Freigabe ab, melden die Agenten
/// das ebenfalls als Fehler (`is_error`, `PostToolUseFailure`); das ist eine Entscheidung und zählt nicht.
public enum ToolFailure {
    /// So viele Fehler eines Turns zeigt die Detailansicht.
    public static let keptCount = 5
    private static let textLength = 90
    /// Texte, mit denen Claude Code, Codex und lumo selbst eine Ablehnung melden.
    private static let denialMarkers = [
        "In lumo abgelehnt", "Denied in lumo", "doesn't want to proceed", "does not want to proceed",
        "was rejected", "rejected this tool", "User denied", "denied by the user", "Permission denied by user",
    ]

    public static func isDenial(_ text: String) -> Bool {
        denialMarkers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// Hängt die erste Zeile von `text` gekürzt an und behält nur die letzten `keptCount`. Auf „Exit code 1“
    /// folgt bei Claude Code die eigentliche Meldung; dann zählen beide Zeilen.
    static func appending(_ text: String?, to list: [String]) -> [String] {
        let lines = (text ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let line = lines.first.map { first in
            first.hasPrefix("Exit code") && lines.count > 1 ? first + " · " + lines[1] : first
        }
        let short = line.map { $0.count > textLength ? String($0.prefix(textLength)) + "…" : $0 } ?? L("Unbekannter Fehler")
        return Array((list + [short]).suffix(keptCount))
    }
}
