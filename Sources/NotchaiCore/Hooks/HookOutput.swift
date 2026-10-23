/// Was `notchai-hook` auf stdout schreibt. Formate geprüft in `docs/hooks.md`.
public enum HookOutput {
    /// Keine Entscheidung: Der Agent fragt wie gewohnt selbst (sein Dialog ist ohnehin schon offen).
    public static let noDecision = ""

    public static func permissionAllow() -> String {
        permission(["behavior": .string("allow")])
    }

    public static func permissionDeny(message: String) -> String {
        permission(["behavior": .string("deny"), "message": .string(message)])
    }

    /// Antwort auf `AskUserQuestion`: `updatedInput` ersetzt die ganze Eingabe, deshalb geht sie
    /// unverändert zurück, ergänzt um `answers` (Fragetext → gewählte Option oder getippter Text).
    public static func questionAnswer(toolInput: JSONValue, answers: [String: String]) -> String {
        var input: [String: JSONValue] = if case .object(let o) = toolInput { o } else { [:] }
        input["answers"] = .object(answers.mapValues { .string($0) })
        return JSONValue.object(["hookSpecificOutput": .object([
            "hookEventName": .string("PreToolUse"),
            "permissionDecision": .string("allow"),
            "updatedInput": .object(input),
        ])]).jsonString()
    }

    private static func permission(_ decision: [String: JSONValue]) -> String {
        JSONValue.object(["hookSpecificOutput": .object([
            "hookEventName": .string("PermissionRequest"),
            "decision": .object(decision),
        ])]).jsonString()
    }
}
