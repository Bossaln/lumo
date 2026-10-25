import Foundation

/// Ein Turn: vom Prompt bis zur fertigen Antwort; `end == nil`, solange er läuft.
public struct TurnSpan: Equatable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }
}

/// Eine vom Agenten geänderte Datei.
public struct EditedFile: Equatable, Sendable {
    public var path: String
    public var at: Date

    public init(path: String, at: Date) {
        self.path = path
        self.at = at
    }
}

/// Was sich aus dem Transkript einer Session ablesen lässt. Die Leser füllen es Zeile für Zeile.
public struct TranscriptSummary: Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String?
    public var cwd: String?
    /// Claude: `cli`, `claude-vscode`, `claude-desktop` …
    public var entrypoint: String?
    /// Codex: `codex_tui`, `codex_exec` …
    public var originator: String?
    public var customTitle: String?
    public var firstPrompt: String?
    public var lastPrompt: String?
    public var model: String?
    /// Belegte Tokens des Kontextfensters nach der letzten Antwort.
    public var contextTokens: Int?
    /// Nur Codex schreibt die Fenstergröße mit; für Claude ergibt sie sich aus dem Modell.
    public var contextWindow: Int?
    /// Nur Codex: Nutzungslimits des Abos aus der letzten `token_count`-Meldung.
    public var usageLimits: UsageLimits?
    public var lastStep: String?
    /// Fehlgeschlagene Werkzeugaufrufe im letzten Turn, ohne Ablehnungen (`ToolFailure.isDenial`).
    public var errorCount = 0
    /// Kurztexte dieser Fehler, neueste zuletzt, höchstens `ToolFailure.keptCount`.
    public var recentErrors: [String] = []
    public var lastActivity: Date?
    public var turnInProgress = false
    public var lastFinishedAt: Date?
    public var lastAssistantText: String?
    /// Zeitpunkte aller echten Prompts (für die Tagesbilanz).
    public var prompts: [Date] = []
    public var turns: [TurnSpan] = []
    public var editedFiles: [EditedFile] = []

    public init(agent: AgentKind) {
        self.agent = agent
    }

    /// Ein neuer Prompt, der zugleich den nächsten Turn startet (Claude).
    mutating func beginTurn(prompt: String, at date: Date) {
        notePrompt(prompt, at: date)
        startTurn(at: date)
    }

    mutating func notePrompt(_ prompt: String, at date: Date) {
        if firstPrompt == nil { firstPrompt = prompt }
        lastPrompt = prompt
        prompts.append(date)
    }

    /// Beendet einen noch offenen Turn (unterbrochen) und startet den nächsten. Fehler zählen je Turn.
    mutating func startTurn(at date: Date) {
        if let last = turns.indices.last, turns[last].end == nil { turns[last].end = date }
        turns.append(TurnSpan(start: date, end: nil))
        turnInProgress = true
        errorCount = 0
        recentErrors = []
    }

    /// Ein fehlgeschlagener Werkzeugaufruf; Ablehnungen durch den Besitzer zählen nicht.
    mutating func noteError(_ text: String?) {
        if let text, ToolFailure.isDenial(text) { return }
        errorCount += 1
        recentErrors = ToolFailure.appending(text, to: recentErrors)
    }

    mutating func endTurn(at date: Date, text: String?) {
        if let last = turns.indices.last, turns[last].end == nil { turns[last].end = date }
        turnInProgress = false
        lastFinishedAt = date
        if let text { lastAssistantText = text }
    }

    mutating func noteActivity(_ date: Date?) {
        guard let date else { return }
        lastActivity = max(lastActivity ?? date, date)
    }
}

/// Zeitstempel der Transkripte (ISO-8601, meist mit Millisekunden).
enum TranscriptDate {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }
}

/// Werte nur mit dem passenden Typ; alles andere zählt als „fehlt“.
extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { o } else { nil }
    }

    var intValue: Int? {
        numberValue.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
    }

    /// Eine Zeile als JSON-Objekt; leere oder kaputte Zeilen ergeben `nil`.
    static func objectLine(_ line: Data) -> JSONValue? {
        guard !line.isEmpty, let value = try? JSONDecoder().decode(JSONValue.self, from: line),
              case .object = value else { return nil }
        return value
    }
}
