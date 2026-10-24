import Foundation

/// Eine offene Anfrage samt Session, für die App sortiert nach Alter.
public struct PendingEntry: Equatable, Sendable {
    public var sessionKey: String
    public var request: PendingRequest
}

/// Führt Hook-Ereignisse (live) und Transkript-Zusammenfassungen (Ergänzung, Startzustand) zu einem
/// Bild aller Sessions zusammen und entscheidet, wann die Notch aufleuchtet. Reine Logik ohne Uhr:
/// Die Zeit kommt immer als `now` von außen.
public struct SessionBook: Sendable {
    /// „Fertig“ wird nach dieser Zeit zu „bereit“.
    static let doneLifetime: TimeInterval = 10 * 60
    /// So lange gilt ein laufender Turn ohne Hooks als „arbeitet“, auch ohne neue Zeile im Transkript.
    static let workingGrace: TimeInterval = 60
    /// Sessions, deren Agent-Prozess notchai nicht kennt (nur aus dem Transkript), verschwinden so lange nach ihrer
    /// letzten Aktivität. Läuft der Prozess nachweislich, bleiben sie, bis er endet.
    static let unconfirmedLifetime: TimeInterval = 30 * 60
    private static let titleLength = 80
    private static let stepLength = 60

    public private(set) var sessions: [String: AgentSession] = [:]
    private var extras: [String: Extras] = [:]

    /// Was nicht direkt in `AgentSession` steht, aber für Titel, Status und Anfragen gebraucht wird.
    private struct Extras: Sendable {
        var customTitle: String?
        var hookTitle: String?
        var firstPrompt: String?
        var lastPrompt: String?
        var model: String?
        /// Offene Anfragen, älteste zuerst (Unteragenten können parallel fragen).
        var pendings: [PendingRequest] = []
        /// Zeitpunkt des letzten Hook-Ereignisses, das den Status gesetzt hat. Danach zählt das
        /// Transkript für den Status nicht mehr.
        var hookStatusAt: Date?
        var hookStepAt: Date?
        var hookErrors = 0
        var transcriptErrors = 0
        var doneAt: Date?
        /// Prozess des Agenten aus dem letzten Hook; endet er, ist die Session vorbei (`removeEnded`).
        var agentPid: Int32?
        /// Von Hand aus der Notch entfernt; neue Aktivität danach holt die Session zurück.
        var dismissedAt: Date?
    }

    public init() {}

    public static func key(_ agent: AgentKind, _ sessionId: String) -> String {
        "\(agent.rawValue):\(sessionId)"
    }

    // MARK: - Hook-Ereignisse

    public mutating func apply(envelope: HookEnvelope, settings: AppSettings, now: Date) -> [SessionChange] {
        let e = envelope.event
        let key = Self.key(envelope.agent, e.sessionId)
        if e.hookEventName == "SessionEnd" {
            let changes = releaseAll(key)
            sessions[key] = nil
            extras[key] = nil
            return changes + (envelope.mode == .decide ? [.release(requestId: envelope.requestId)] : [])
        }

        var session = sessions[key] ?? Self.newSession(key: key, agent: envelope.agent, sessionId: e.sessionId, now: now)
        var extra = extras[key] ?? Extras()
        session.host.merge(env: envelope.env)
        if let pid = envelope.agentPid { extra.agentPid = pid }
        if let cwd = e.cwd { session.cwd = cwd; session.projectName = Self.projectName(cwd) }
        session.lastActivity = max(session.lastActivity, now)
        extra.hookTitle = e.sessionTitle ?? extra.hookTitle
        extra.model = e.model ?? extra.model
        session.model = e.model ?? session.model
        var changes: [SessionChange] = []

        switch (e.hookEventName, envelope.mode) {
        case ("PermissionRequest", .decide):
            guard settings.watches(envelope.agent) else {
                changes.append(.release(requestId: envelope.requestId))
                break
            }
            let tool = e.toolName ?? "Werkzeug"
            extra.pendings.append(PendingRequest(
                requestId: envelope.requestId, kind: .permission(tool: tool, summary: Self.permissionSummary(tool, e.toolInput)),
                toolInput: e.toolInput, createdAt: now, deadline: now.addingTimeInterval(settings.clampedApprovalTimeout)))
            extra.hookStatusAt = now
            if settings.signalOnPermission { changes.append(.raise(sessionKey: key, trigger: .permission)) }
        case ("PreToolUse", .decide) where e.toolName == "AskUserQuestion":
            guard settings.watches(envelope.agent), let question = Self.question(from: e.toolInput) else {
                changes.append(.release(requestId: envelope.requestId))
                break
            }
            extra.pendings.append(PendingRequest(
                requestId: envelope.requestId, kind: .question(question), toolInput: e.toolInput,
                createdAt: now, deadline: now.addingTimeInterval(settings.clampedApprovalTimeout)))
            extra.hookStatusAt = now
            if settings.signalOnQuestion { changes.append(.raise(sessionKey: key, trigger: .question)) }
        case (_, .decide):
            // Entscheidungen gibt es nur für Freigaben und Fragen.
            changes.append(.release(requestId: envelope.requestId))
        case ("SessionStart", _):
            extra.hookStatusAt = extra.hookStatusAt ?? now
        case ("UserPromptSubmit", _):
            changes += releaseAll(&extra, key: key)
            if let prompt = e.prompt, !prompt.hasPrefix("<") {
                extra.firstPrompt = extra.firstPrompt ?? prompt
                extra.lastPrompt = prompt
            }
            session.status = .working
            extra.hookStatusAt = now
        case ("PreToolUse", _):
            if let tool = e.toolName {
                session.lastStep = StepDescriber.describe(tool: tool, input: e.toolInput)
                extra.hookStepAt = now
            }
            session.status = .working
            extra.hookStatusAt = now
        case ("PostToolUse", _), ("PostToolUseFailure", _):
            if e.hookEventName == "PostToolUseFailure" { extra.hookErrors += 1 }
            changes += release(&extra, key: key) { Self.matches($0, tool: e.toolName, input: e.toolInput) }
            session.status = .working
            extra.hookStatusAt = now
        case ("Notification", _):
            switch e.notificationType {
            case "idle_prompt":
                changes += releaseAll(&extra, key: key)
                session.status = .ready
                extra.hookStatusAt = now
            case "permission_prompt", "agent_needs_input", "elicitation_dialog":
                // Mit offener Anfrage meldet Claude nur dieselbe Frage noch einmal.
                guard extra.pendings.isEmpty else { break }
                session.status = .waitingAnswer
                extra.hookStatusAt = now
                if settings.signalOnQuestion { changes.append(.raise(sessionKey: key, trigger: .question)) }
            default:
                break
            }
        case ("Stop", _):
            changes += releaseAll(&extra, key: key)
            session.status = .done
            extra.doneAt = now
            if let text = e.lastAssistantMessage.flatMap(Self.firstLine) {
                session.lastStep = Self.shorten("Fertig: " + text, to: Self.stepLength)
                extra.hookStepAt = now
            }
            extra.hookStatusAt = now
            if settings.signalOnDone { changes.append(.raise(sessionKey: key, trigger: .done)) }
        case ("StopFailure", _):
            changes += releaseAll(&extra, key: key)
            session.status = .error
            session.lastStep = Self.shorten("Fehler: " + (e.error ?? e.message ?? "unbekannt"), to: Self.stepLength)
            extra.hookStepAt = now
            extra.hookStatusAt = now
            if settings.signalOnError { changes.append(.raise(sessionKey: key, trigger: .error)) }
        default:
            break
        }

        store(&session, extra, key: key)
        return changes
    }

    // MARK: - Transkripte

    public mutating func apply(summary: TranscriptSummary, settings: AppSettings, now: Date) -> [SessionChange] {
        guard let sessionId = summary.sessionId else { return [] }
        let key = Self.key(summary.agent, sessionId)
        var session = sessions[key]
            ?? Self.newSession(key: key, agent: summary.agent, sessionId: sessionId, now: summary.lastActivity ?? now)
        var extra = extras[key] ?? Extras()

        if let cwd = summary.cwd { session.cwd = cwd; session.projectName = Self.projectName(cwd) }
        extra.customTitle = summary.customTitle ?? extra.customTitle
        extra.firstPrompt = summary.firstPrompt ?? extra.firstPrompt
        extra.lastPrompt = summary.lastPrompt ?? extra.lastPrompt
        let model = summary.model ?? extra.model
        let limit = summary.agent == .codex ? summary.contextWindow : ContextWindow.claudeLimit(model: model)
        session.contextFraction = ContextWindow.fraction(tokens: summary.contextTokens, limit: limit) ?? session.contextFraction
        session.model = model ?? session.model
        if let tokens = summary.contextTokens { session.contextTokens = tokens; session.contextLimit = limit }
        session.usageLimits = summary.usageLimits ?? session.usageLimits
        session.startedAt = [summary.prompts.first, summary.turns.first?.start].compactMap { $0 }.min() ?? session.startedAt
        session.promptCount = summary.prompts.count
        session.editedFileCount = Set(summary.editedFiles.map(\.path)).count
        if let step = summary.lastStep, extra.hookStepAt.map({ (summary.lastActivity ?? .distantPast) > $0 }) ?? true {
            session.lastStep = step
        }
        extra.transcriptErrors = summary.errorCount
        if let activity = summary.lastActivity { session.lastActivity = max(session.lastActivity, activity) }
        session.host.originator = summary.originator ?? session.host.originator
        session.host.entrypoint = session.host.entrypoint ?? summary.entrypoint

        // Ohne Hooks (noch nicht eingerichtet, bei Codex nicht bestätigt) liest sich der Status aus dem Transkript.
        if extra.hookStatusAt == nil, extra.pendings.isEmpty {
            if summary.turnInProgress, let last = summary.lastActivity, now.timeIntervalSince(last) < Self.workingGrace {
                session.status = .working
            } else if let finished = summary.lastFinishedAt, !summary.turnInProgress {
                extra.doneAt = finished
                session.status = now.timeIntervalSince(finished) >= Self.doneLifetime ? .ready : .done
            } else {
                session.status = .ready
            }
        }

        store(&session, extra, key: key)
        return []
    }

    // MARK: - Entscheidungen und Zeit

    /// Die Anfrage ist in der Notch entschieden worden; die Session arbeitet weiter.
    public mutating func resolvePending(requestId: UUID) -> [SessionChange] {
        guard let key = extras.first(where: { $0.value.pendings.contains { $0.requestId == requestId } })?.key,
              var extra = extras[key], var session = sessions[key] else { return [] }
        extra.pendings.removeAll { $0.requestId == requestId }
        session.status = .working
        store(&session, extra, key: key)
        return [.clear(sessionKey: key)]
    }

    /// Läuft regelmäßig: abgelaufene Anfragen verschwinden aus der Notch, „fertig“ wird zu „bereit“.
    public mutating func tick(now: Date) -> (changes: [SessionChange], expired: [UUID]) {
        var changes: [SessionChange] = []
        var expired: [UUID] = []
        for key in sessions.keys.sorted() {
            guard var session = sessions[key], var extra = extras[key] else { continue }
            let gone = extra.pendings.filter { $0.deadline < now }
            if !gone.isEmpty {
                // Der Dialog des Agenten bleibt offen; die Session wartet weiter, nur nicht mehr in der Notch.
                extra.pendings.removeAll { $0.deadline < now }
                expired += gone.map(\.requestId)
                changes.append(.clear(sessionKey: key))
            }
            if session.status == .done, let doneAt = extra.doneAt, now.timeIntervalSince(doneAt) >= Self.doneLifetime {
                session.status = .ready
            }
            store(&session, extra, key: key)
        }
        return (changes, expired)
    }

    /// Entfernt Sessions, deren Agent-Prozess nicht mehr läuft (Terminal oder App geschlossen, ohne `SessionEnd`).
    public mutating func removeEnded(isAlive: (Int32) -> Bool) -> [SessionChange] {
        var changes: [SessionChange] = []
        for key in extras.keys.sorted() {
            guard let pid = extras[key]?.agentPid, !isAlive(pid) else { continue }
            changes += releaseAll(key)
            sessions[key] = nil
            extras[key] = nil
        }
        return changes
    }

    /// Nimmt eine Session aus der Notch, bis sie wieder etwas tut. Eine offene Anfrage geht zurück an den Agenten.
    public mutating func dismiss(_ key: String, now: Date) -> [SessionChange] {
        guard sessions[key] != nil, var extra = extras[key] else { return [] }
        let changes = releaseAll(&extra, key: key)
        extra.dismissedAt = now
        if var session = sessions[key] {
            if session.status.isWaiting { session.status = .ready }
            store(&session, extra, key: key)
        }
        return changes
    }

    /// Alle offenen Anfragen, älteste zuerst.
    public func pendingRequests() -> [PendingEntry] {
        extras.flatMap { key, extra in extra.pendings.map { PendingEntry(sessionKey: key, request: $0) } }
            .sorted { ($0.request.createdAt, $0.request.requestId.uuidString) < ($1.request.createdAt, $1.request.requestId.uuidString) }
    }

    /// Sessions für die Übersicht: nur beobachtete Agenten, nicht älter als eingestellt; wartende zuerst
    /// (älteste Anfrage vorn), dann arbeitende, fehlerhafte und fertige, jeweils die jüngste zuerst.
    public func visibleSessions(settings: AppSettings, now: Date) -> [AgentSession] {
        let maxAge = TimeInterval(settings.sessionMaxAgeHours) * 3600
        return sessions.values
            .filter { settings.watches($0.agent) && now.timeIntervalSince($0.lastActivity) <= maxAge && isShown($0, now: now) }
            .map { session in
                var s = session
                if let extra = extras[s.id] { s.title = Self.title(extra, projectName: s.projectName, source: settings.sessionTitleSource) }
                return s
            }
            .sorted { a, b in
                let (ra, rb) = (Self.rank(a.status), Self.rank(b.status))
                if ra != rb { return ra < rb }
                if a.status.isWaiting {
                    let (da, db) = (a.pending?.createdAt ?? a.lastActivity, b.pending?.createdAt ?? b.lastActivity)
                    if da != db { return da < db }
                } else if a.lastActivity != b.lastActivity {
                    return a.lastActivity > b.lastActivity
                }
                return a.id < b.id
            }
    }

    // MARK: - Hilfen

    /// Von Hand entfernt und seitdem still, oder zu lange still, ohne dass ein eigener Prozess zeigt, dass sie noch
    /// offen ist: nicht zeigen.
    private func isShown(_ session: AgentSession, now: Date) -> Bool {
        guard let extra = extras[session.id] else { return true }
        if let dismissed = extra.dismissedAt, session.lastActivity <= dismissed { return false }
        if !provesOpen(extra, host: session.host), session.pending == nil,
           now.timeIntervalSince(session.lastActivity) > Self.unconfirmedLifetime { return false }
        return true
    }

    /// Ein Agent-Prozess nur für diese Session, außerhalb der Apps: Solange er läuft, ist die Session offen. Die
    /// Codex-App führt alle Threads über einen Prozess, und in beiden Apps läuft der Prozess weiter, wenn der Chat zu ist.
    private func provesOpen(_ extra: Extras, host: SessionHost) -> Bool {
        guard let pid = extra.agentPid, host.source != .claudeApp, host.source != .codexApp else { return false }
        return extras.values.filter { $0.agentPid == pid }.count == 1
    }

    private static func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .waitingApproval, .waitingAnswer: 0
        case .working: 1
        case .error: 2
        case .done, .ready: 3
        }
    }

    private static func newSession(key: String, agent: AgentKind, sessionId: String, now: Date) -> AgentSession {
        AgentSession(id: key, agent: agent, sessionId: sessionId, title: "", projectName: "Unbekannt", cwd: nil,
                     status: .ready, lastStep: nil, errorCount: 0, contextFraction: nil, lastActivity: now,
                     pending: nil, host: SessionHost())
    }

    /// Schreibt Session und Zusatzdaten zurück; offene Anfragen bestimmen dabei Status und `pending`.
    private mutating func store(_ session: inout AgentSession, _ extra: Extras, key: String) {
        var extra = extra
        extra.pendings.sort { $0.createdAt < $1.createdAt }
        session.pending = extra.pendings.first
        switch session.pending?.kind {
        case .permission: session.status = .waitingApproval
        case .question: session.status = .waitingAnswer
        case nil: break
        }
        session.errorCount = max(extra.hookErrors, extra.transcriptErrors)
        session.title = Self.title(extra, projectName: session.projectName, source: .lastPrompt)
        sessions[key] = session
        extras[key] = extra
    }

    private mutating func releaseAll(_ key: String) -> [SessionChange] {
        guard var extra = extras[key] else { return [] }
        let changes = releaseAll(&extra, key: key)
        extras[key] = extra
        return changes
    }

    private func releaseAll(_ extra: inout Extras, key: String) -> [SessionChange] {
        release(&extra, key: key) { _ in true }
    }

    /// Entfernt passende Anfragen: Sie sind anderswo beantwortet (im Terminal) oder überholt.
    private func release(_ extra: inout Extras, key: String, where matches: (PendingRequest) -> Bool) -> [SessionChange] {
        let released = extra.pendings.filter(matches)
        guard !released.isEmpty else { return [] }
        extra.pendings.removeAll(where: matches)
        return [.clear(sessionKey: key)] + released.map { .release(requestId: $0.requestId) }
    }

    /// Gehört ein ausgeführtes Werkzeug zu dieser Anfrage? Gleiches Werkzeug und alle Felder der
    /// ursprünglichen Eingabe unverändert (Fragen kommen mit zusätzlichem `answers` zurück).
    private static func matches(_ pending: PendingRequest, tool: String?, input: JSONValue?) -> Bool {
        guard let tool, pending.kind.toolName == tool else { return false }
        guard let expected = pending.toolInput?.objectValue else { return pending.toolInput == nil || pending.toolInput == input }
        guard let actual = input?.objectValue else { return false }
        return expected.allSatisfy { actual[$0.key] == $0.value }
    }

    private static func permissionSummary(_ tool: String, _ input: JSONValue?) -> String {
        switch tool {
        case "Bash", "exec_command", "shell":
            let command = input?["command"]?.stringValue ?? input?["cmd"]?.stringValue
            return command.flatMap(firstLine).map { shorten($0, to: 200) } ?? StepDescriber.describe(tool: tool, input: input)
        case "WebFetch":
            return input?["url"]?.stringValue ?? StepDescriber.describe(tool: tool, input: input)
        default:
            return StepDescriber.describe(tool: tool, input: input)
        }
    }

    private static func question(from input: JSONValue?) -> QuestionPrompt? {
        guard let questions = input?["questions"]?.arrayValue, let first = questions.first,
              let text = first["question"]?.stringValue, !text.isEmpty else { return nil }
        return QuestionPrompt(question: text, header: first["header"]?.stringValue,
                              options: (first["options"]?.arrayValue ?? []).compactMap { $0["label"]?.stringValue },
                              multiSelect: first["multiSelect"]?.boolValue ?? false, moreCount: questions.count - 1)
    }

    private static func title(_ extra: Extras, projectName: String, source: SessionTitleSource) -> String {
        let custom = extra.customTitle ?? extra.hookTitle
        let candidates = switch source {
        case .lastPrompt: [extra.lastPrompt, custom, extra.firstPrompt]
        case .sessionTitle: [custom, extra.lastPrompt, extra.firstPrompt]
        }
        for candidate in candidates {
            let line = (candidate ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !line.isEmpty { return shorten(line, to: titleLength) }
        }
        return projectName
    }

    private static func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private static func firstLine(_ text: String) -> String? {
        let line = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return line?.isEmpty == false ? line : nil
    }

    private static func shorten(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length)) + "…" : text
    }
}
