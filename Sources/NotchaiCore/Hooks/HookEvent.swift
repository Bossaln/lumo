import Foundation

/// Welcher Agent ein Ereignis schickt. Dasselbe wie der Agent eines Signals.
public typealias AgentKind = SignalAgent

/// Eingabe, die Claude Code und Codex jedem Hook auf stdin geben (Felder siehe `docs/hooks.md`).
/// Unbekannte Felder werden ignoriert; ein Feld in unerwarteter Form fehlt einfach, statt das ganze
/// Ereignis unlesbar zu machen. Nur `session_id` und `hook_event_name` sind Pflicht.
public struct HookEvent: Codable, Equatable, Sendable {
    public var hookEventName: String
    public var sessionId: String
    public var transcriptPath: String?
    public var cwd: String?
    public var permissionMode: String?
    public var prompt: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var toolUseId: String?
    public var error: String?
    public var message: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var source: String?
    public var sessionTitle: String?
    public var model: String?
    public var turnId: String?
    /// Nur bei Ereignissen aus einem Unteragenten: seine ID und Art (`Explore`, `general-purpose` …). Unteragenten
    /// schicken sonst dieselbe `session_id` wie die Haupt-Session.
    public var agentId: String?
    public var agentType: String?

    public init(hookEventName: String, sessionId: String) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case prompt
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case error, message
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case source
        case sessionTitle = "session_title"
        case model
        case turnId = "turn_id"
        case agentId = "agent_id"
        case agentType = "agent_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        func text(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        transcriptPath = text(.transcriptPath)
        cwd = text(.cwd)
        permissionMode = text(.permissionMode)
        prompt = text(.prompt)
        toolName = text(.toolName)
        toolInput = (try? c.decodeIfPresent(JSONValue.self, forKey: .toolInput)) ?? nil
        toolUseId = text(.toolUseId)
        error = text(.error)
        message = text(.message)
        notificationType = text(.notificationType)
        lastAssistantMessage = text(.lastAssistantMessage)
        source = text(.source)
        sessionTitle = text(.sessionTitle)
        model = text(.model)
        turnId = text(.turnId)
        agentId = text(.agentId)
        agentType = text(.agentType)
    }
}
