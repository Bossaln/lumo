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
        /// Fehler des laufenden Turns aus Hooks bzw. Transkript, je mit Kurztexten.
        var hookErrors = 0
        var hookErrorTexts: [String] = []
        var transcriptErrors = 0
        var transcriptErrorTexts: [String] = []
        /// Der laufende Turn endete mit `StopFailure`; ein späteres `Stop` überdeckt das nicht.
        var turnFailed = false
        /// Fertig oder Fehler seit diesem Zeitpunkt; danach wird die Session wieder „bereit“.
        var doneAt: Date?
        /// Ein Transkript gehört dazu (`transcript_path` im Hook oder vom Transkript-Leser). Echte Sessions haben
        /// immer eins; Ereignisse ohne (von Hand an `notchai-hook` geschickt) ergeben keine Session in der Liste.
        var hasTranscript = false
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
        if e.transcriptPath != nil { extra.hasTranscript = true }
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
            let tool = e.toolName ?? L("Werkzeug")
            extra.pendings.append(PendingRequest(
                requestId: envelope.requestId, kind: .permission(tool: tool, summary: PermissionText.summary(tool: tool, input: e.toolInput)),
                toolInput: e.toolInput, createdAt: now, deadline: now.addingTimeInterval(settings.clampedApprovalTimeout)))
            extra.hookStatusAt = now
            if settings.signalOnPermission { changes.append(.raise(sessionKey: key, trigger: .permission)) }
        case ("PreToolUse", .decide) where e.toolName == "AskUserQuestion":
            let questions = Self.questions(from: e.toolInput)
            guard settings.watches(envelope.agent), !questions.isEmpty else {
                changes.append(.release(requestId: envelope.requestId))
                break
            }
            extra.pendings.append(PendingRequest(
                requestId: envelope.requestId, kind: .question(questions), toolInput: e.toolInput,
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
            extra.hookErrors = 0
            extra.hookErrorTexts = []
            extra.turnFailed = false
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
            if e.hookEventName == "PostToolUseFailure", !(e.error.map(ToolFailure.isDenial) ?? false) {
                extra.hookErrors += 1
                extra.hookErrorTexts = ToolFailure.appending(e.error, to: extra.hookErrorTexts)
            }
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
        case ("Stop", _) where extra.turnFailed:
            // Der Fehler dieses Turns bleibt stehen; sein Signal kam schon.
            changes += releaseAll(&extra, key: key)
            session.status = .error
            extra.hookStatusAt = now
        case ("Stop", _):
            changes += releaseAll(&extra, key: key)
            session.status = .done
            extra.doneAt = now
            if let text = e.lastAssistantMessage.flatMap(Self.firstLine) {
                session.lastStep = Self.shorten(L("Fertig: {0}", text), to: Self.stepLength)
                extra.hookStepAt = now
            }
            extra.hookStatusAt = now
            if settings.signalOnDone { changes.append(.raise(sessionKey: key, trigger: .done)) }
        case ("StopFailure", _):
            changes += releaseAll(&extra, key: key)
            session.status = .error
            extra.turnFailed = true
            extra.doneAt = now
            session.lastStep = Self.shorten(L("Fehler: {0}", e.error ?? e.message ?? L("unbekannt")), to: Self.stepLength)
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
        extra.hasTranscript = true

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
        session.editedFileCount = Self.projectFiles(summary.editedFiles, cwd: session.cwd).count
        if let step = summary.lastStep, extra.hookStepAt.map({ (summary.lastActivity ?? .distantPast) > $0 }) ?? true {
            session.lastStep = step
        }
        extra.transcriptErrors = summary.errorCount
        extra.transcriptErrorTexts = summary.recentErrors
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

    /// Eine Antwort auf die gerade offene Frage der Anfrage `requestId`. Sind damit alle Fragen beantwortet, kommen
    /// alle Antworten zurück (zum Abschicken); sonst `nil`, und die Notch zeigt die nächste Frage.
    public mutating func recordAnswer(requestId: UUID, answer: String) -> [String: String]? {
        guard let key = extras.first(where: { $0.value.pendings.contains { $0.requestId == requestId } })?.key,
              var extra = extras[key], var session = sessions[key],
              let index = extra.pendings.firstIndex(where: { $0.requestId == requestId }),
              let current = extra.pendings[index].currentQuestion else { return nil }
        extra.pendings[index].answers[current.prompt.question] = answer
        let request = extra.pendings[index]
        store(&session, extra, key: key)
        return request.currentQuestion == nil ? request.answers : nil
    }

    /// Die Anfrage ist anderswo entschieden worden (im Terminal erlaubt, der Befehl läuft schon): aus der Notch
    /// nehmen und den wartenden Hook beenden.
    public mutating func answeredElsewhere(requestId: UUID) -> [SessionChange] {
        guard let key = extras.first(where: { $0.value.pendings.contains { $0.requestId == requestId } })?.key,
              var extra = extras[key], var session = sessions[key] else { return [] }
        let changes = release(&extra, key: key) { $0.requestId == requestId }
        session.status = .working
        store(&session, extra, key: key)
        return changes
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
            if session.status == .done || session.status == .error, let doneAt = extra.doneAt,
               now.timeIntervalSince(doneAt) >= Self.doneLifetime {
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

    /// Für die Diagnose in den Entwickleroptionen: jede bekannte Session, auch versteckte, mit Herkunft, Prozess und ob
    /// die Notch sie zeigt. Ohne Titel und Prompts.
    public func diagnosticLines(settings: AppSettings, now: Date) -> [String] {
        let shown = Set(visibleSessions(settings: settings, now: now).map(\.id))
        return sessions.values.sorted { $0.id < $1.id }.map { s in
            let h = s.host
            let pid = extras[s.id]?.agentPid.map(String.init) ?? "-"
            let fields = [
                "source=\(s.host.source)", "pid=\(pid)", "entrypoint=\(h.entrypoint ?? "-")",
                "originator=\(h.originator ?? "-")", "bundle=\(h.bundleId ?? "-")", "term=\(h.termProgram ?? "-")",
                "status=\(s.status)", "idle=\(Int(now.timeIntervalSince(s.lastActivity) / 60))min",
                shown.contains(s.id) ? "shown" : "hidden",
            ]
            return s.id + " " + fields.joined(separator: " ")
        }
    }

    // MARK: - Hilfen

    /// Von Hand entfernt und seitdem still, oder zu lange still, ohne dass ein eigener Prozess zeigt, dass sie noch
    /// offen ist: nicht zeigen.
    private func isShown(_ session: AgentSession, now: Date) -> Bool {
        guard let extra = extras[session.id] else { return true }
        if let dismissed = extra.dismissedAt, session.lastActivity <= dismissed { return false }
        if !extra.hasTranscript, session.pending == nil { return false }
        if !provesOpen(session, extra), session.pending == nil,
           now.timeIntervalSince(session.lastActivity) > Self.unconfirmedLifetime { return false }
        return true
    }

    /// Ein Agent-Prozess außerhalb der Apps: Solange er läuft, ist die Session offen. Teilen sich mehrere
    /// Claude-Sessions einen Prozess (`/resume`, `/clear`), gehört er der zuletzt aktiven; die älteren gelten nicht
    /// mehr als offen. Codex führt dagegen mehrere Threads über einen Prozess (App, App-Server), auch wenn die App
    /// nicht erkennbar ist; dann beweist er für keinen etwas. In beiden Apps läuft der Prozess weiter, wenn der Chat
    /// zu ist.
    private func provesOpen(_ session: AgentSession, _ extra: Extras) -> Bool {
        guard let pid = extra.agentPid, session.host.source != .claudeApp, session.host.source != .codexApp else { return false }
        let sharing = sessions.values.filter { extras[$0.id]?.agentPid == pid }
        if session.agent == .codex { return sharing.count == 1 }
        let owner = sharing.max { ($0.lastActivity, $0.id) < ($1.lastActivity, $1.id) }
        return owner?.id == session.id
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
        AgentSession(id: key, agent: agent, sessionId: sessionId, title: "", projectName: L("Unbekannt"), cwd: nil,
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
        session.recentErrors = extra.transcriptErrors >= extra.hookErrors ? extra.transcriptErrorTexts : extra.hookErrorTexts
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

    /// Alle Fragen von `AskUserQuestion`; Fragen ohne Text fallen weg.
    private static func questions(from input: JSONValue?) -> [QuestionPrompt] {
        (input?["questions"]?.arrayValue ?? []).compactMap { item in
            guard let text = item["question"]?.stringValue, !text.isEmpty else { return nil }
            return QuestionPrompt(question: text, header: item["header"]?.stringValue,
                                  options: (item["options"]?.arrayValue ?? []).compactMap { $0["label"]?.stringValue },
                                  multiSelect: item["multiSelect"]?.boolValue ?? false)
        }
    }

    /// Geänderte Dateien im Projektordner; Notizen, Pläne oder Zwischenablagen des Agenten anderswo zählen nicht.
    static func projectFiles(_ files: [EditedFile], cwd: String?) -> Set<String> {
        let paths = Set(files.map(\.path))
        guard let cwd, !cwd.isEmpty else { return paths }
        let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return paths.filter { $0.hasPrefix(root) || !$0.hasPrefix("/") }
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
