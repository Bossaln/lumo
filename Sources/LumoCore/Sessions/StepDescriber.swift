import Foundation

/// Kurze deutsche Beschreibung eines Werkzeugaufrufs für die Session-Zeile („Bearbeitet NotchShape.swift“).
public enum StepDescriber {
    private static let maxLength = 60

    public static func describe(tool: String, input: JSONValue?) -> String {
        switch tool {
        case "Bash", "exec_command", "shell":
            guard let command = command(input), !command.isEmpty else { return L("Führt einen Befehl aus") }
            return L("Führt aus: {0}", shorten(firstLine(command)))
        case "Edit", "MultiEdit":
            return file("Bearbeitet {0}", input?["file_path"]?.stringValue) ?? tool
        case "NotebookEdit":
            return file("Bearbeitet {0}", input?["notebook_path"]?.stringValue) ?? tool
        case "apply_patch":
            return file("Bearbeitet {0}", patchFiles(patchText(input)).first) ?? L("Bearbeitet Dateien")
        case "Write":
            return file("Schreibt {0}", input?["file_path"]?.stringValue) ?? tool
        case "Read":
            return file("Liest {0}", input?["file_path"]?.stringValue) ?? tool
        case "Grep", "Glob":
            guard let pattern = input?["pattern"]?.stringValue else { return L("Sucht") }
            return L("Sucht {0}", shorten(firstLine(pattern)))
        case "WebFetch", "WebSearch": return L("Recherchiert im Web")
        case "AskUserQuestion": return L("Fragt dich")
        case "Task", "Agent": return L("Startet Unteragent")
        case "TodoWrite", "update_plan": return L("Plant")
        default: return tool
        }
    }

    /// Dateien aus einem `apply_patch`-Text (`*** Add/Update/Delete File: <pfad>`).
    public static func patchFiles(_ patch: String?) -> [String] {
        guard let patch else { return [] }
        let prefixes = ["*** Add File: ", "*** Update File: ", "*** Delete File: "]
        return patch.split(separator: "\n").compactMap { line in
            prefixes.first { line.hasPrefix($0) }.map { String(line.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Der Patch steht bei Codex direkt als Text da oder unter `input`.
    static func patchText(_ input: JSONValue?) -> String? {
        input?.stringValue ?? input?["input"]?.stringValue ?? input?["patch"]?.stringValue
    }

    private static func command(_ input: JSONValue?) -> String? {
        if let text = input?["command"]?.stringValue ?? input?["cmd"]?.stringValue { return text }
        guard let parts = (input?["command"] ?? input?["cmd"])?.arrayValue?.compactMap(\.stringValue), !parts.isEmpty else { return nil }
        // `["bash", "-lc", "<befehl>"]`: Gemeint ist der eigentliche Befehl.
        if parts.count >= 3, ["bash", "zsh", "sh"].contains((parts[0] as NSString).lastPathComponent), parts[1].hasPrefix("-") {
            return parts.last
        }
        return parts.joined(separator: " ")
    }

    /// `phrase` ist ein Text mit `{0}` für den Dateinamen („Liest {0}“).
    private static func file(_ phrase: String, _ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return L(phrase, shorten((path as NSString).lastPathComponent))
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
    }

    private static func shorten(_ text: String) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }
}
