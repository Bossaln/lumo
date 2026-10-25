import Foundation

/// Liest ein Claude-Transkript (`~/.claude/projects/<projekt>/<session>.jsonl`) Zeile für Zeile.
/// Gezählt werden nur `user`- und `assistant`-Zeilen der Hauptsession; Unteragenten (`isSidechain`)
/// und mitgeschriebene API-Anfragen bleiben außen vor (`docs/hooks.md`).
public struct ClaudeTranscriptReader: Sendable {
    public private(set) var summary = TranscriptSummary(agent: .claude)

    /// Werkzeuge, deren `file_path` bzw. `notebook_path` als geänderte Datei zählt.
    private static let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]
    /// Modell-Kennung von Meldungen, die Claude Code selbst erzeugt (etwa API-Fehler).
    private static let syntheticModel = "<synthetic>"

    public init() {}

    public mutating func consume(line: Data) {
        // Große mitgeschriebene API-Anfragen gar nicht erst dekodieren.
        if line.range(of: Data(#""type":"api-request"#.utf8)) != nil { return }
        guard let row = JSONValue.objectLine(line), let type = row["type"]?.stringValue else { return }
        switch type {
        case "custom-title":
            if let title = row["customTitle"]?.stringValue { summary.customTitle = title }
        case "last-prompt":
            if let prompt = row["lastPrompt"]?.stringValue { summary.lastPrompt = prompt }
        case "user", "assistant":
            guard row["isSidechain"]?.boolValue != true else { return }
            let date = TranscriptDate.parse(row["timestamp"]?.stringValue)
            summary.sessionId = row["sessionId"]?.stringValue ?? summary.sessionId
            summary.cwd = row["cwd"]?.stringValue ?? summary.cwd
            summary.entrypoint = row["entrypoint"]?.stringValue ?? summary.entrypoint
            summary.noteActivity(date)
            if type == "user" { consumeUser(row, at: date) } else { consumeAssistant(row, at: date) }
        default:
            break
        }
    }

    private mutating func consumeUser(_ row: JSONValue, at date: Date?) {
        let content = row["message"]?["content"]
        let blocks = content?.arrayValue ?? []
        for block in blocks where block["type"]?.stringValue == "tool_result" && block["is_error"]?.boolValue == true {
            summary.noteError(Self.resultText(block["content"]))
        }
        guard row["isMeta"]?.boolValue != true, row["toolUseResult"] == nil, let date else { return }
        let texts = content?.stringValue.map { [$0] } ?? blocks.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }
        // Befehls-Ausgaben, Erinnerungen usw. beginnen mit einem Tag und sind keine Prompts.
        guard let prompt = texts.first(where: { !$0.hasPrefix("<") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
        summary.beginTurn(prompt: prompt, at: date)
    }

    /// Text eines `tool_result`: eine Zeichenkette oder Textblöcke.
    private static func resultText(_ content: JSONValue?) -> String? {
        if let text = content?.stringValue { return text }
        let texts = (content?.arrayValue ?? []).compactMap { $0["text"]?.stringValue }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private mutating func consumeAssistant(_ row: JSONValue, at date: Date?) {
        guard let message = row["message"] else { return }
        if let model = message["model"]?.stringValue, model != Self.syntheticModel { summary.model = model }
        if let usage = message["usage"] {
            let tokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0]?.intValue }
            if !tokens.isEmpty { summary.contextTokens = tokens.reduce(0, +) }
        }
        let blocks = message["content"]?.arrayValue ?? []
        for block in blocks where block["type"]?.stringValue == "tool_use" {
            guard let name = block["name"]?.stringValue else { continue }
            let input = block["input"]
            summary.lastStep = StepDescriber.describe(tool: name, input: input)
            if Self.editTools.contains(name), let date,
               let path = input?["file_path"]?.stringValue ?? input?["notebook_path"]?.stringValue {
                summary.editedFiles.append(EditedFile(path: path, at: date))
            }
        }
        if message["stop_reason"]?.stringValue == "end_turn", let date {
            let text = blocks.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
            summary.endTurn(at: date, text: text)
        }
    }
}
