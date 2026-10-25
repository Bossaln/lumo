import Foundation

/// `event`: nur melden, der Hook wartet nicht. `decide`: der Hook wartet auf eine Entscheidung.
public enum HookMode: String, Codable, Sendable {
    case event, decide
}

/// Was `lumo-hook` an die App schickt: das Ereignis samt Absender und ausgewählter Umgebung.
public struct HookEnvelope: Codable, Sendable {
    public var requestId: UUID
    public var agent: AgentKind
    public var mode: HookMode
    public var event: HookEvent
    public var env: [String: String]
    public var sentAt: Date
    /// Prozess des Agenten, der den Hook gestartet hat (`ProcessTree.agent`). Endet er, ist die Session vorbei,
    /// auch ohne `SessionEnd` (Terminal geschlossen). Ältere Hook-Programme schicken ihn nicht.
    public var agentPid: Int32?

    public init(requestId: UUID, agent: AgentKind, mode: HookMode, event: HookEvent, env: [String: String], sentAt: Date,
                agentPid: Int32? = nil) {
        self.requestId = requestId
        self.agent = agent
        self.mode = mode
        self.event = event
        self.env = env
        self.sentAt = sentAt
        self.agentPid = agentPid
    }
}

/// Antwort der App auf eine `decide`-Anfrage. `stdout == ""` heißt „keine Entscheidung“.
public struct HookReply: Codable, Sendable, Equatable {
    public var requestId: UUID
    public var stdout: String

    public init(requestId: UUID, stdout: String) {
        self.requestId = requestId
        self.stdout = stdout
    }
}
