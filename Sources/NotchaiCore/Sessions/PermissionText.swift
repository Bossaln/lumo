import Foundation

/// Was eine Freigabe zeigt: eine Kurzfassung für die Signale und, wenn die nicht alles zeigt, den vollen Befehl.
/// Wer erlaubt, soll nie etwas freigeben, das er nicht sehen konnte: Ein zweizeiliger Befehl sieht in der
/// Kurzfassung harmlos aus, wenn nur die erste Zeile da steht.
public enum PermissionText {
    /// Bis hierhin passt ein Befehl sicher in eine Zeile der Signale; längere bekommen einen Hinweis.
    public static let shortLength = 60
    private static let summaryLength = 200
    private static let shellTools: Set<String> = ["Bash", "exec_command", "shell"]

    /// Erste Zeile des Befehls (Shell), die URL (WebFetch) oder die Beschreibung des Werkzeugs.
    public static func summary(tool: String, input: JSONValue?) -> String {
        if shellTools.contains(tool), let command = command(input), let line = firstLine(command) {
            return shorten(line, to: summaryLength)
        }
        if tool == "WebFetch", let url = input?["url"]?.stringValue { return url }
        return StepDescriber.describe(tool: tool, input: input)
    }

    /// Der ganze Shell-Befehl, wenn er mehrere Zeilen hat oder länger als `shortLength` ist; sonst `nil`.
    public static func fullCommand(tool: String, input: JSONValue?) -> String? {
        guard shellTools.contains(tool), let command = command(input)?.trimmingCharacters(in: .whitespacesAndNewlines),
              lineCount(command) > 1 || command.count > shortLength else { return nil }
        return command
    }

    /// Hinweis neben der Kurzfassung, der nie gekürzt werden darf: „+2 Zeilen“ oder „ganzer Befehl“.
    public static func note(for full: String) -> String {
        let more = lineCount(full) - 1
        switch more {
        case ..<1: return L("ganzer Befehl")
        case 1: return L("+1 Zeile")
        default: return L("+{0} Zeilen", more)
        }
    }

    /// Textstück, an dem sich der laufende Befehl unter den Prozessen des Agenten erkennen lässt: der Anfang der
    /// ersten Zeile bis zum ersten `'` (Claude Code reicht den Befehl in `eval '…'` weiter und schreibt `'`
    /// dabei um). Zu kurze Stücke wären mehrdeutig und ergeben `nil`.
    public static func processNeedle(tool: String, input: JSONValue?) -> String? {
        guard shellTools.contains(tool), let line = command(input).flatMap(firstLine) else { return nil }
        let needle = String(line.prefix { $0 != "'" }.prefix(80)).trimmingCharacters(in: .whitespaces)
        return needle.count >= 6 ? needle : nil
    }

    private static func command(_ input: JSONValue?) -> String? {
        input?["command"]?.stringValue ?? input?["cmd"]?.stringValue
    }

    private static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Erste nicht leere Zeile; davor stehende Leerzeilen könnten sonst den eigentlichen Befehl verstecken.
    private static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    private static func shorten(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length)) + "…" : text
    }
}
