import Foundation

/// Liest ein Codex-Rollout (`~/.codex/sessions/<jahr>/<monat>/<tag>/rollout-….jsonl`) Zeile für Zeile.
/// Jede Zeile ist `{timestamp, type, payload}` (bestätigt in `docs/hooks.md`, Abschnitt 5).
/// Turns beginnen mit `task_started` und enden mit `task_complete`; Prompts sind Nutzer-Nachrichten.
public struct CodexRolloutReader: Sendable {
    public private(set) var summary = TranscriptSummary(agent: .codex)

    public init() {}

    public mutating func consume(line: Data) {
        guard let row = JSONValue.objectLine(line), let type = row["type"]?.stringValue,
              let payload = row["payload"] else { return }
        let date = TranscriptDate.parse(row["timestamp"]?.stringValue)
        summary.noteActivity(date)
        switch type {
        case "session_meta":
            summary.sessionId = payload["id"]?.stringValue ?? summary.sessionId
            summary.cwd = payload["cwd"]?.stringValue ?? summary.cwd
            summary.originator = payload["originator"]?.stringValue ?? summary.originator
        case "turn_context":
            summary.model = payload["model"]?.stringValue ?? summary.model
        case "event_msg":
            consumeEvent(payload, at: date)
        case "response_item":
            consumeItem(payload, at: date)
        default:
            break
        }
    }

    private mutating func consumeEvent(_ payload: JSONValue, at date: Date?) {
        switch payload["type"]?.stringValue {
        case "task_started":
            if let window = payload["model_context_window"]?.intValue { summary.contextWindow = window }
            if let date { summary.startTurn(at: date) }
        case "task_complete":
            if let date { summary.endTurn(at: date, text: payload["last_agent_message"]?.stringValue) }
        case "token_count":
            let limitId = payload["rate_limits"]?["limit_id"]?.stringValue
            if limitId == nil || limitId == UsageLimits.codexLimitId,
               let limits = UsageLimits(codex: payload["rate_limits"], at: date) {
                summary.usageLimits = limits
            }
            guard let info = payload["info"] else { return }
            if let tokens = info["last_token_usage"]?["total_tokens"]?.intValue { summary.contextTokens = tokens }
            if let window = info["model_context_window"]?.intValue { summary.contextWindow = window }
        case "error":
            summary.noteError(payload["message"]?.stringValue)
        default:
            break
        }
    }

    private mutating func consumeItem(_ payload: JSONValue, at date: Date?) {
        switch payload["type"]?.stringValue {
        case "message":
            guard payload["role"]?.stringValue == "user", let date else { return }
            let texts = (payload["content"]?.arrayValue ?? [])
                .filter { $0["type"]?.stringValue == "input_text" }
                .compactMap { $0["text"]?.stringValue }
            // Umgebungsangaben (`<environment_context>` …) kommen ebenfalls als Nutzer-Nachricht.
            guard let prompt = texts.first(where: { !$0.hasPrefix("<") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }
            summary.notePrompt(prompt, at: date)
        case "function_call", "custom_tool_call":
            guard let name = payload["name"]?.stringValue else { return }
            // `function_call` liefert die Argumente als JSON-Text, `custom_tool_call` als rohen Text.
            let input: JSONValue? = if let arguments = payload["arguments"]?.stringValue {
                (try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))) ?? .string(arguments)
            } else {
                payload["input"]
            }
            summary.lastStep = StepDescriber.describe(tool: name, input: input)
            if name == "apply_patch", let date {
                for path in StepDescriber.patchFiles(StepDescriber.patchText(input)) {
                    summary.editedFiles.append(EditedFile(path: absolute(path), at: date))
                }
            }
        default:
            break
        }
    }

    /// Patch-Pfade sind meist relativ zum Arbeitsordner der Session.
    private func absolute(_ path: String) -> String {
        guard !path.hasPrefix("/"), let cwd = summary.cwd else { return path }
        return URL(filePath: cwd).appending(path: path).path
    }
}

/// Titel der Codex-Sessions aus `~/.codex/session_index.jsonl`.
public enum CodexSessionIndex {
    /// `id` → `thread_name`; spätere Zeilen gewinnen (Codex hängt Umbenennungen an).
    public static func titles(from lines: [Data]) -> [String: String] {
        var titles: [String: String] = [:]
        for line in lines {
            guard let row = JSONValue.objectLine(line), let id = row["id"]?.stringValue,
                  let name = row["thread_name"]?.stringValue, !name.isEmpty else { continue }
            titles[id] = name
        }
        return titles
    }
}
