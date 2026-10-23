import Foundation

public enum SessionStatus: Equatable, Sendable {
    case working, waitingApproval, waitingAnswer, done, ready, error

    public var isWaiting: Bool {
        self == .waitingApproval || self == .waitingAnswer
    }
}

/// Eine Frage von `AskUserQuestion`. Gezeigt wird nur die erste; `moreCount` zählt die übrigen.
public struct QuestionPrompt: Equatable, Sendable {
    public var question: String
    public var header: String?
    public var options: [String]
    public var multiSelect: Bool
    public var moreCount: Int

    public init(question: String, header: String?, options: [String], multiSelect: Bool, moreCount: Int) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
        self.moreCount = moreCount
    }
}

public enum PendingKind: Equatable, Sendable {
    case permission(tool: String, summary: String)
    case question(QuestionPrompt)

    /// Werkzeug, dessen Aufruf auf die Entscheidung wartet.
    public var toolName: String {
        switch self {
        case .permission(let tool, _): tool
        case .question: "AskUserQuestion"
        }
    }
}

/// Eine Freigabe oder Frage, auf die ein `notchai-hook` gerade wartet.
public struct PendingRequest: Equatable, Sendable {
    public var requestId: UUID
    public var kind: PendingKind
    public var toolInput: JSONValue?
    public var createdAt: Date
    /// Danach zeigt die Notch die Anfrage nicht mehr; der Agent fragt dann selbst weiter.
    public var deadline: Date

    public init(requestId: UUID, kind: PendingKind, toolInput: JSONValue?, createdAt: Date, deadline: Date) {
        self.requestId = requestId
        self.kind = kind
        self.toolInput = toolInput
        self.createdAt = createdAt
        self.deadline = deadline
    }
}

/// Wo eine Session läuft; daraus ergibt sich, wohin eine Antwort geht (`ReplyRouter`).
public struct SessionHost: Equatable, Sendable {
    public var entrypoint: String?
    public var bundleId: String?
    public var termProgram: String?
    public var cmuxSurface: String?
    public var messagingSocket: String?
    public var originator: String?

    public init(entrypoint: String? = nil, bundleId: String? = nil, termProgram: String? = nil,
                cmuxSurface: String? = nil, messagingSocket: String? = nil, originator: String? = nil) {
        self.entrypoint = entrypoint
        self.bundleId = bundleId
        self.termProgram = termProgram
        self.cmuxSurface = cmuxSurface
        self.messagingSocket = messagingSocket
        self.originator = originator
    }

    /// Übernimmt, was die Umgebung eines Hooks verrät; Fehlendes bleibt wie es war.
    mutating func merge(env: [String: String]) {
        entrypoint = env["CLAUDE_CODE_ENTRYPOINT"] ?? entrypoint
        bundleId = env["__CFBundleIdentifier"] ?? bundleId
        termProgram = env["TERM_PROGRAM"] ?? termProgram
        messagingSocket = env["CLAUDE_CODE_MESSAGING_SOCKET"] ?? messagingSocket
        let surfaceKey = env["CMUX_SURFACE_ID"] != nil ? "CMUX_SURFACE_ID"
            : env.keys.filter { $0.hasPrefix("CMUX_") && $0.contains("SURFACE") }.sorted().first
        if let surfaceKey, let surface = env[surfaceKey] { cmuxSurface = surface }
    }
}

/// Eine Session, wie die Notch sie zeigt.
public struct AgentSession: Identifiable, Equatable, Sendable {
    /// `"<agent>:<session_id>"` – Sessions im selben Ordner bleiben so getrennt.
    public var id: String
    public var agent: AgentKind
    public var sessionId: String
    public var title: String
    public var projectName: String
    public var cwd: String?
    public var status: SessionStatus
    public var lastStep: String?
    public var errorCount: Int
    /// Wie voll das Kontextfenster ist (0…1); `nil`, solange unbekannt.
    public var contextFraction: Double?
    public var lastActivity: Date
    /// Älteste offene Anfrage dieser Session.
    public var pending: PendingRequest?
    public var host: SessionHost

    public init(id: String, agent: AgentKind, sessionId: String, title: String, projectName: String, cwd: String?,
                status: SessionStatus, lastStep: String?, errorCount: Int, contextFraction: Double?, lastActivity: Date,
                pending: PendingRequest?, host: SessionHost) {
        self.id = id
        self.agent = agent
        self.sessionId = sessionId
        self.title = title
        self.projectName = projectName
        self.cwd = cwd
        self.status = status
        self.lastStep = lastStep
        self.errorCount = errorCount
        self.contextFraction = contextFraction
        self.lastActivity = lastActivity
        self.pending = pending
        self.host = host
    }
}

public enum SignalTrigger: Equatable, Sendable {
    case permission, question, done, error
}

/// Was das Session-Buch der App meldet.
public enum SessionChange: Equatable, Sendable {
    /// Die Notch soll für diese Session aufleuchten.
    case raise(sessionKey: String, trigger: SignalTrigger)
    /// Ein Signal dieser Session ist erledigt.
    case clear(sessionKey: String)
    /// Auf diese Anfrage wartet ein Hook, aber notchai entscheidet sie nicht (mehr): sofort
    /// „keine Entscheidung“ schicken, damit der Hook endet.
    case release(requestId: UUID)
}

extension AppSettings {
    public func watches(_ agent: AgentKind) -> Bool {
        switch agent {
        case .claude: watchClaude
        case .codex: watchCodex
        }
    }

    /// Wie lange die Notch eine Anfrage zeigt; der Hook wartet höchstens 125 s, der Agent 130 s.
    public var clampedApprovalTimeout: TimeInterval {
        TimeInterval(min(max(approvalTimeoutSeconds, 5), 125))
    }
}
