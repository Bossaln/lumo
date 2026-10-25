import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_683_988)

private func envelope(_ name: String, session: String = "s1", agent: AgentKind = .claude, mode: HookMode = .event,
                      cwd: String = "/Users/test/Developer/lumo", tool: String? = nil, input: String? = nil,
                      env: [String: String] = [:], id: UUID = UUID(),
                      configure: (inout HookEvent) -> Void = { _ in }) -> HookEnvelope {
    var event = HookEvent(hookEventName: name, sessionId: session)
    // Echte Sessions haben immer ein Transkript; ohne zeigt die Liste sie nicht.
    event.transcriptPath = "/Users/test/.claude/projects/lumo/\(session).jsonl"
    event.cwd = cwd
    event.toolName = tool
    event.toolInput = input.map { try! JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    configure(&event)
    return HookEnvelope(requestId: id, agent: agent, mode: mode, event: event, env: env, sentAt: t0)
}

private let questionInput = #"""
{"questions":[{"question":"Welche Farbe?","header":"Farbe","options":[{"label":"Rot"},{"label":"Blau"}],"multiSelect":false},
              {"question":"Wie groß?","options":[{"label":"Klein"}]}]}
"""#

@Test func sameFolderTwoSessionsStaySeparate() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("SessionStart", session: "a"), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("SessionStart", session: "b"), settings: .default, now: t0)
    #expect(book.sessions.count == 2)
    #expect(Set(book.sessions.keys) == ["claude:a", "claude:b"])
    #expect(book.sessions["claude:a"]?.projectName == "lumo")
}

@Test func permissionRequestCreatesPendingAndRaises() throws {
    var book = SessionBook()
    let id = UUID()
    let changes = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash",
                                                input: #"{"command":"npm install\nnpm test"}"#, id: id),
                             settings: .default, now: t0)
    #expect(changes == [.raise(sessionKey: "claude:s1", trigger: .permission)])
    let s = try #require(book.sessions["claude:s1"])
    #expect(s.status == .waitingApproval)
    #expect(s.pending?.requestId == id)
    #expect(s.pending?.kind == .permission(tool: "Bash", summary: "npm install"))
    #expect(s.pending?.deadline == t0.addingTimeInterval(120))
}

@Test func askUserQuestionParsesAllQuestions() throws {
    var book = SessionBook()
    let changes = book.apply(envelope: envelope("PreToolUse", mode: .decide, tool: "AskUserQuestion", input: questionInput),
                             settings: .default, now: t0)
    #expect(changes == [.raise(sessionKey: "claude:s1", trigger: .question)])
    let s = try #require(book.sessions["claude:s1"])
    #expect(s.status == .waitingAnswer)
    #expect(s.pending?.kind == .question([
        QuestionPrompt(question: "Welche Farbe?", header: "Farbe", options: ["Rot", "Blau"], multiSelect: false),
        QuestionPrompt(question: "Wie groß?", header: nil, options: ["Klein"], multiSelect: false),
    ]))
    #expect(s.pending?.toolInput?["questions"]?.arrayValue?.count == 2)
}

@Test func questionWithoutQuestionsIsReleasedAtOnce() {
    // Nichts zu zeigen: Der Hook bekommt sofort „keine Entscheidung“, und Claude fragt selbst.
    var book = SessionBook()
    let id = UUID()
    let changes = book.apply(envelope: envelope("PreToolUse", mode: .decide, tool: "AskUserQuestion", input: #"{"questions":[]}"#, id: id),
                             settings: .default, now: t0)
    #expect(changes == [.release(requestId: id)])
    #expect(book.sessions["claude:s1"]?.pending == nil)
}

@Test func decideForUnwatchedAgentIsReleasedAtOnce() {
    var book = SessionBook()
    var settings = AppSettings.default
    settings.watchCodex = false
    let id = UUID()
    let changes = book.apply(envelope: envelope("PermissionRequest", agent: .codex, mode: .decide, tool: "exec_command", id: id),
                             settings: settings, now: t0)
    #expect(changes == [.release(requestId: id)])
}

@Test func answeredInTerminalReleasesPending() throws {
    // Claude beendet den wartenden Hook nicht, wenn im Terminal geantwortet wird (`docs/hooks.md`, Abschnitt 1).
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", input: #"{"command":"ls"}"#, id: id),
                   settings: .default, now: t0)
    // Ein anderes Werkzeug (etwa eines Unteragenten) gibt die Anfrage nicht frei.
    let other = book.apply(envelope: envelope("PostToolUse", tool: "Read", input: #"{"file_path":"/x"}"#), settings: .default, now: t0)
    #expect(other.isEmpty)
    #expect(book.sessions["claude:s1"]?.pending?.requestId == id)
    let changes = book.apply(envelope: envelope("PostToolUse", tool: "Bash", input: #"{"command":"ls","description":"x"}"#),
                             settings: .default, now: t0)
    #expect(changes == [.clear(sessionKey: "claude:s1"), .release(requestId: id)])
    #expect(book.sessions["claude:s1"]?.pending == nil)
    #expect(book.sessions["claude:s1"]?.status == .working)
}

@Test func answeredQuestionInTerminalReleasesPending() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: envelope("PreToolUse", mode: .decide, tool: "AskUserQuestion", input: questionInput, id: id),
                   settings: .default, now: t0)
    // Nach der Antwort trägt die Eingabe zusätzlich `answers`.
    var event = HookEvent(hookEventName: "PostToolUse", sessionId: "s1")
    event.toolName = "AskUserQuestion"
    var input = try! JSONDecoder().decode(JSONValue.self, from: Data(questionInput.utf8)).objectValue!
    input["answers"] = .object(["Welche Farbe?": .string("Rot")])
    event.toolInput = .object(input)
    let changes = book.apply(envelope: HookEnvelope(requestId: UUID(), agent: .claude, mode: .event, event: event, env: [:], sentAt: t0),
                             settings: .default, now: t0)
    #expect(changes.contains(.release(requestId: id)))
}

@Test func stopReleasesPendingAndMarksDone() throws {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", input: #"{"command":"ls"}"#, id: id),
                   settings: .default, now: t0)
    let changes = book.apply(envelope: envelope("Stop") { $0.lastAssistantMessage = "Alles erledigt.\nDetails folgen." },
                             settings: .default, now: t0)
    #expect(changes == [.clear(sessionKey: "claude:s1"), .release(requestId: id), .raise(sessionKey: "claude:s1", trigger: .done)])
    #expect(book.sessions["claude:s1"]?.lastStep == "Fertig: Alles erledigt.")
}

@Test func stopMarksDoneAndThenReady() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("Stop"), settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .done)
    _ = book.tick(now: t0.addingTimeInterval(9 * 60))
    #expect(book.sessions["claude:s1"]?.status == .done)
    _ = book.tick(now: t0.addingTimeInterval(11 * 60))
    #expect(book.sessions["claude:s1"]?.status == .ready)
}

@Test func expiredPendingIsCleared() {
    var book = SessionBook()
    var settings = AppSettings.default
    settings.approvalTimeoutSeconds = 5
    let id = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", id: id), settings: settings, now: t0)
    let early = book.tick(now: t0.addingTimeInterval(4))
    #expect(early.expired.isEmpty)
    let late = book.tick(now: t0.addingTimeInterval(6))
    #expect(late.expired == [id])
    #expect(late.changes.contains(.clear(sessionKey: "claude:s1")))
    #expect(book.sessions["claude:s1"]?.pending == nil)
    // Der Dialog des Agenten ist noch offen: Die Session wartet weiter, nur ohne Knöpfe in der Notch.
    #expect(book.sessions["claude:s1"]?.status == .waitingApproval)
}

@Test func timeoutIsClampedToHookLimits() {
    var book = SessionBook()
    var settings = AppSettings.default
    settings.approvalTimeoutSeconds = 500
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash"), settings: settings, now: t0)
    #expect(book.sessions["claude:s1"]?.pending?.deadline == t0.addingTimeInterval(125))
}

@Test func signalSettingsSuppressRaise() {
    var book = SessionBook()
    var settings = AppSettings.default
    settings.signalOnDone = false
    settings.signalOnError = false
    settings.signalOnPermission = false
    #expect(book.apply(envelope: envelope("Stop"), settings: settings, now: t0).isEmpty)
    #expect(book.apply(envelope: envelope("StopFailure") { $0.error = "rate_limit" }, settings: settings, now: t0).isEmpty)
    // Die Freigabe wartet trotzdem in der Liste, nur ohne Signal.
    #expect(book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash"), settings: settings, now: t0).isEmpty)
    #expect(book.sessions["claude:s1"]?.status == .waitingApproval)
}

@Test func stopFailureMarksError() {
    var book = SessionBook()
    let changes = book.apply(envelope: envelope("StopFailure") { $0.error = "rate_limit" }, settings: .default, now: t0)
    #expect(changes == [.raise(sessionKey: "claude:s1", trigger: .error)])
    #expect(book.sessions["claude:s1"]?.status == .error)
    #expect(book.sessions["claude:s1"]?.lastStep == "Fehler: rate_limit")
}

@Test func notificationWithoutPendingAsksForAttention() {
    var book = SessionBook()
    let changes = book.apply(envelope: envelope("Notification") { $0.notificationType = "agent_needs_input" },
                             settings: .default, now: t0)
    #expect(changes == [.raise(sessionKey: "claude:s1", trigger: .question)])
    #expect(book.sessions["claude:s1"]?.status == .waitingAnswer)
    #expect(book.sessions["claude:s1"]?.pending == nil)
}

@Test func permissionNotificationDuringPendingChangesNothing() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash"), settings: .default, now: t0)
    let changes = book.apply(envelope: envelope("Notification") { $0.notificationType = "permission_prompt" },
                             settings: .default, now: t0)
    #expect(changes.isEmpty)
    #expect(book.sessions["claude:s1"]?.pending != nil)
}

@Test func idlePromptMakesReady() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("UserPromptSubmit"), settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .working)
    _ = book.apply(envelope: envelope("Notification") { $0.notificationType = "idle_prompt" }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .ready)
}

@Test func preToolUseEventKeepsWaitingStatusButNotesStep() {
    // Das asynchrone PreToolUse-Ereignis kann nach der Frage ankommen; die Session wartet trotzdem.
    var book = SessionBook()
    _ = book.apply(envelope: envelope("PreToolUse", mode: .decide, tool: "AskUserQuestion", input: questionInput), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("PreToolUse", tool: "AskUserQuestion", input: questionInput), settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .waitingAnswer)
    #expect(book.sessions["claude:s1"]?.lastStep == "Fragt dich")
}

@Test func sessionEndRemovesSession() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", id: id), settings: .default, now: t0)
    let changes = book.apply(envelope: envelope("SessionEnd"), settings: .default, now: t0)
    #expect(changes == [.clear(sessionKey: "claude:s1"), .release(requestId: id)])
    #expect(book.sessions.isEmpty)
}

@Test func resolvePendingReturnsToWorking() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", id: id), settings: .default, now: t0)
    #expect(book.resolvePending(requestId: id) == [.clear(sessionKey: "claude:s1")])
    #expect(book.sessions["claude:s1"]?.status == .working)
    #expect(book.resolvePending(requestId: id).isEmpty)
}

@Test func secondRequestWaitsBehindTheFirst() {
    // Unteragenten können parallel fragen; gezeigt wird die älteste Anfrage, die nächste rückt nach.
    var book = SessionBook()
    let first = UUID(), second = UUID()
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Bash", id: first), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("PermissionRequest", mode: .decide, tool: "Write", id: second), settings: .default,
                   now: t0.addingTimeInterval(1))
    #expect(book.sessions["claude:s1"]?.pending?.requestId == first)
    #expect(book.pendingRequests().map(\.request.requestId) == [first, second])
    _ = book.resolvePending(requestId: first)
    #expect(book.sessions["claude:s1"]?.pending?.requestId == second)
    #expect(book.sessions["claude:s1"]?.status == .waitingApproval)
}

@Test func hostComesFromEnvironment() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("SessionStart", env: ["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "vscode",
                                                            "__CFBundleIdentifier": "com.microsoft.VSCode",
                                                            "CMUX_PANEL_SURFACE": "surface:7",
                                                            "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/cc.sock"]),
                   settings: .default, now: t0)
    let host = book.sessions["claude:s1"]?.host
    #expect(host == SessionHost(entrypoint: "cli", bundleId: "com.microsoft.VSCode", termProgram: "vscode",
                                cmuxSurface: "surface:7", messagingSocket: "/tmp/cc.sock", originator: nil))
    _ = book.apply(envelope: envelope("Stop", env: ["CMUX_SURFACE_ID": "surface:9"]), settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.host.cmuxSurface == "surface:9")
    #expect(book.sessions["claude:s1"]?.host.termProgram == "vscode")
}

// MARK: - Transkripte

private func summary(_ agent: AgentKind = .claude, session: String = "s1", configure: (inout TranscriptSummary) -> Void) -> TranscriptSummary {
    var s = TranscriptSummary(agent: agent)
    s.sessionId = session
    s.cwd = "/Users/test/Developer/lumo"
    configure(&s)
    return s
}

@Test func transcriptOnlySessionGetsStatusFromSummary() {
    var book = SessionBook()
    _ = book.apply(summary: summary {
        $0.turnInProgress = true
        $0.lastActivity = t0.addingTimeInterval(-10)
        $0.model = "claude-opus-5-5"
        $0.contextTokens = 250_000
    }, settings: .default, now: t0)
    let s = book.sessions["claude:s1"]
    #expect(s?.status == .working)
    #expect(s?.contextFraction == 0.25)
    // Ein Turn ohne Lebenszeichen seit über einer Minute gilt nicht mehr als „arbeitet“.
    _ = book.apply(summary: summary { $0.turnInProgress = true; $0.lastActivity = t0.addingTimeInterval(-120) },
                   settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .ready)
    _ = book.apply(summary: summary { $0.lastFinishedAt = t0.addingTimeInterval(-60); $0.lastActivity = t0.addingTimeInterval(-60) },
                   settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .done)
}

@Test func hookStatusWinsOverTranscript() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("Stop"), settings: .default, now: t0)
    _ = book.apply(summary: summary { $0.turnInProgress = true; $0.lastActivity = t0 }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .done)
}

@Test func hookStepWinsOverOlderTranscriptStep() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("PreToolUse", tool: "Read", input: #"{"file_path":"/a/neu.swift"}"#), settings: .default, now: t0)
    _ = book.apply(summary: summary { $0.lastStep = "Liest alt.swift"; $0.lastActivity = t0.addingTimeInterval(-5) },
                   settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.lastStep == "Liest neu.swift")
    _ = book.apply(summary: summary { $0.lastStep = "Schreibt später.swift"; $0.lastActivity = t0.addingTimeInterval(5) },
                   settings: .default, now: t0.addingTimeInterval(5))
    #expect(book.sessions["claude:s1"]?.lastStep == "Schreibt später.swift")
}

@Test func errorCountIsMaximumOfHookAndTranscript() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("PostToolUseFailure", tool: "Bash"), settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.errorCount == 1)
    _ = book.apply(summary: summary { $0.errorCount = 3; $0.lastActivity = t0 }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.errorCount == 3)
}

@Test func codexWindowComesFromTranscript() {
    var book = SessionBook()
    _ = book.apply(summary: summary(.codex) {
        $0.contextTokens = 22168
        $0.contextWindow = 258_400
        $0.originator = "codex_tui"
        $0.lastActivity = t0
    }, settings: .default, now: t0)
    let s = book.sessions["codex:s1"]
    #expect(s?.contextFraction == 22168.0 / 258_400.0)
    #expect(s?.host.originator == "codex_tui")
}

@Test func titleFollowsSetting() {
    var book = SessionBook()
    _ = book.apply(summary: summary {
        $0.customTitle = "Notch-Form bauen"
        $0.firstPrompt = "Baue die Notch-Form"
        $0.lastPrompt = "Jetzt die Farben\nund dann die Schrift"
        $0.lastActivity = t0
    }, settings: .default, now: t0)
    var settings = AppSettings.default
    #expect(book.visibleSessions(settings: settings, now: t0).first?.title == "Jetzt die Farben und dann die Schrift")
    settings.sessionTitleSource = .sessionTitle
    #expect(book.visibleSessions(settings: settings, now: t0).first?.title == "Notch-Form bauen")
    _ = book.apply(summary: summary { $0.lastActivity = t0 }, settings: settings, now: t0)
    // Ohne Prompt und Titel bleibt der Projektname.
    var empty = SessionBook()
    _ = empty.apply(summary: summary { $0.lastActivity = t0 }, settings: settings, now: t0)
    #expect(empty.visibleSessions(settings: settings, now: t0).first?.title == "lumo")
}

@Test func longTitlesAreCut() {
    var book = SessionBook()
    _ = book.apply(summary: summary { $0.lastPrompt = String(repeating: "a", count: 100); $0.lastActivity = t0 },
                   settings: .default, now: t0)
    #expect(book.visibleSessions(settings: .default, now: t0).first?.title == String(repeating: "a", count: 80) + "…")
}

@Test func visibleSessionsOrderAndFilter() {
    var book = SessionBook()
    _ = book.apply(envelope: envelope("Stop", session: "fertig"), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("UserPromptSubmit", session: "arbeitet"), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("PermissionRequest", session: "wartet", mode: .decide, tool: "Bash"), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("StopFailure", session: "kaputt"), settings: .default, now: t0)
    _ = book.apply(envelope: envelope("UserPromptSubmit", session: "codex", agent: .codex), settings: .default, now: t0)
    _ = book.apply(summary: summary(session: "alt") { $0.lastActivity = t0.addingTimeInterval(-25 * 3600) }, settings: .default, now: t0)
    var settings = AppSettings.default
    settings.watchCodex = false
    let order = book.visibleSessions(settings: settings, now: t0).map(\.sessionId)
    #expect(order == ["wartet", "arbeitet", "kaputt", "fertig"])
}

// MARK: - Kontextfenster und Zeiten

@Test func opus55HasOneMillionWindow() { #expect(ContextWindow.claudeLimit(model: "claude-opus-5-5") == 1_000_000) }
@Test func oneMillionVariantsAndFamilies() {
    #expect(ContextWindow.claudeLimit(model: "claude-sonnet-4-5[1m]") == 1_000_000)
    #expect(ContextWindow.claudeLimit(model: "claude-fable-5-1") == 1_000_000)
    #expect(ContextWindow.claudeLimit(model: "claude-opus-4-7") == 1_000_000)
    #expect(ContextWindow.claudeLimit(model: "claude-opus-4-1") == 200_000)
    #expect(ContextWindow.claudeLimit(model: nil) == 200_000)
}
@Test func unknownModelHas200k() { #expect(ContextWindow.claudeLimit(model: "claude-3-haiku") == 200_000) }
@Test func fractionIsClamped() {
    #expect(ContextWindow.fraction(tokens: 300_000, limit: 200_000) == 1.0)
    #expect(ContextWindow.fraction(tokens: nil, limit: 200_000) == nil)
    #expect(ContextWindow.fraction(tokens: 5, limit: 0) == nil)
}
@Test func relativeTimes() {
    #expect(RelativeTime.short(from: t0, now: t0.addingTimeInterval(30)) == "jetzt")
    #expect(RelativeTime.short(from: t0, now: t0.addingTimeInterval(120)) == "vor 2 min")
    #expect(RelativeTime.short(from: t0, now: t0.addingTimeInterval(2 * 3600)) == "vor 2 h")
    #expect(RelativeTime.short(from: t0, now: t0.addingTimeInterval(3 * 86400)) == "vor 3 T")
    #expect(RelativeTime.short(from: t0, now: t0.addingTimeInterval(-5)) == "jetzt")
}
