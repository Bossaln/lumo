import Foundation
import Testing
@testable import NotchaiCore

private let t0 = Date(timeIntervalSince1970: 1_792_950_000)

private func event(_ name: String, session: String = "s1", pid: Int32? = nil, mode: HookMode = .event,
                   transcript: Bool = true, id: UUID = UUID(), configure: (inout HookEvent) -> Void = { _ in }) -> HookEnvelope {
    var e = HookEvent(hookEventName: name, sessionId: session)
    e.cwd = "/Users/test/Developer/notchai"
    if transcript { e.transcriptPath = "/Users/test/.claude/projects/notchai/\(session).jsonl" }
    configure(&e)
    return HookEnvelope(requestId: id, agent: .claude, mode: mode, event: e, env: [:], sentAt: t0, agentPid: pid)
}

private func visible(_ book: SessionBook, at date: Date) -> [String] {
    book.visibleSessions(settings: .default, now: date).map(\.sessionId).sorted()
}

private let twoQuestions = try! JSONDecoder().decode(JSONValue.self, from: Data(#"""
{"questions":[{"question":"Welche Signale?","options":[{"label":"Freigabe"},{"label":"Fertig"}],"multiSelect":true},
              {"question":"Wie lange?","options":[{"label":"Kurz"},{"label":"Lang"}]}]}
"""#.utf8))

// MARK: - Sessions ohne Transkript, geteilter Prozess (#11)

@Test func eventsWithoutTranscriptMakeNoSession() {
    // Von Hand an `notchai-hook` geschickt: Das ist keine echte Session.
    var book = SessionBook()
    _ = book.apply(envelope: event("UserPromptSubmit", session: "fake", pid: 42, transcript: false) { $0.prompt = "Fehler-Signal testen" },
                   settings: .default, now: t0)
    _ = book.apply(envelope: event("StopFailure", session: "fake", pid: 42, transcript: false) { $0.error = "Testfehler" },
                   settings: .default, now: t0)
    #expect(visible(book, at: t0).isEmpty)
    // Kommt ein Transkript dazu, ist sie echt.
    var summary = TranscriptSummary(agent: .claude)
    summary.sessionId = "fake"
    summary.lastActivity = t0
    _ = book.apply(summary: summary, settings: .default, now: t0)
    #expect(visible(book, at: t0) == ["fake"])
}

@Test func sharedProcessBelongsToTheLatestSession() {
    // `/resume` oder `/clear` im selben Claude-Prozess: Die neue Session bleibt, solange er läuft; die alte verblasst.
    var book = SessionBook()
    _ = book.apply(envelope: event("Stop", session: "old", pid: 4242), settings: .default, now: t0)
    _ = book.apply(envelope: event("Stop", session: "new", pid: 4242), settings: .default, now: t0.addingTimeInterval(60))
    _ = book.removeEnded { _ in true }
    #expect(visible(book, at: t0.addingTimeInterval(20 * 60)) == ["new", "old"])
    #expect(visible(book, at: t0.addingTimeInterval(3 * 3600)) == ["new"])
}

@Test func errorFadesToReadyLikeDone() {
    var book = SessionBook()
    _ = book.apply(envelope: event("StopFailure", pid: 4242) { $0.error = "API nicht erreichbar" }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.status == .error)
    _ = book.tick(now: t0.addingTimeInterval(11 * 60))
    #expect(book.sessions["claude:s1"]?.status == .ready)
    #expect(book.sessions["claude:s1"]?.lastStep == "Fehler: API nicht erreichbar")
}

// MARK: - Fehler und Fertig im selben Turn (#22)

@Test func stopAfterFailureKeepsTheError() {
    var book = SessionBook()
    _ = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "los" }, settings: .default, now: t0)
    _ = book.apply(envelope: event("StopFailure") { $0.error = "API-Fehler" }, settings: .default, now: t0)
    let changes = book.apply(envelope: event("Stop") { $0.lastAssistantMessage = "Erledigt" }, settings: .default, now: t0)
    #expect(!changes.contains(.raise(sessionKey: "claude:s1", trigger: .done)))
    #expect(book.sessions["claude:s1"]?.status == .error)
    #expect(book.sessions["claude:s1"]?.lastStep == "Fehler: API-Fehler")
    // Der nächste Prompt beginnt neu.
    _ = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "nochmal" }, settings: .default, now: t0)
    let next = book.apply(envelope: event("Stop") { $0.lastAssistantMessage = "Erledigt" }, settings: .default, now: t0)
    #expect(next.contains(.raise(sessionKey: "claude:s1", trigger: .done)))
}

// MARK: - Fehlerzähler (#17)

@Test func deniedToolsAreNotErrorsAndCountsStartPerTurn() {
    var book = SessionBook()
    _ = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "eins" }, settings: .default, now: t0)
    _ = book.apply(envelope: event("PostToolUseFailure") { $0.toolName = "Bash"; $0.error = "Exit code 1\nls: x: No such file" },
                   settings: .default, now: t0)
    _ = book.apply(envelope: event("PostToolUseFailure") { $0.toolName = "Bash"; $0.error = "In notchai abgelehnt" },
                   settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.errorCount == 1)
    #expect(book.sessions["claude:s1"]?.recentErrors == ["Exit code 1 · ls: x: No such file"])
    _ = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "zwei" }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.errorCount == 0)
    #expect(book.sessions["claude:s1"]?.recentErrors == [])
}

@Test func transcriptErrorsCountPerTurnWithoutDenials() {
    var reader = ClaudeTranscriptReader()
    func line(_ json: String) { reader.consume(line: Data(json.utf8)) }
    line(#"{"type":"user","sessionId":"s1","timestamp":"2026-10-25T10:00:00.000Z","message":{"role":"user","content":"eins"}}"#)
    line(#"{"type":"user","sessionId":"s1","timestamp":"2026-10-25T10:00:05.000Z","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"Exit code 1"}]}}"#)
    #expect(reader.summary.errorCount == 1)
    line(#"{"type":"user","sessionId":"s1","timestamp":"2026-10-25T10:01:00.000Z","message":{"role":"user","content":"zwei"}}"#)
    line(#"{"type":"user","sessionId":"s1","timestamp":"2026-10-25T10:01:05.000Z","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"In notchai abgelehnt"}]}}"#)
    line(#"{"type":"user","sessionId":"s1","timestamp":"2026-10-25T10:01:06.000Z","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":[{"type":"text","text":"The user doesn't want to proceed with this tool use."}]}]}}"#)
    #expect(reader.summary.errorCount == 0)
    #expect(reader.summary.recentErrors.isEmpty)
}

// MARK: - Geänderte Dateien (#19)

@Test func onlyFilesInTheProjectCount() {
    let files = ["/Users/test/Developer/notchai/a.swift", "/Users/test/Developer/notchai/b/c.swift",
                 "/Users/test/Developer/notchai-other/x.swift", "/private/tmp/scratch/issue.md",
                 "/Users/test/.claude/projects/x/memory/MEMORY.md"]
        .map { EditedFile(path: $0, at: t0) }
    #expect(SessionBook.projectFiles(files, cwd: "/Users/test/Developer/notchai")
        == ["/Users/test/Developer/notchai/a.swift", "/Users/test/Developer/notchai/b/c.swift"])
    #expect(SessionBook.projectFiles(files, cwd: nil).count == 5)
}

// MARK: - Mehrere Fragen (#15)

@Test func allQuestionsAreAnsweredBeforeTheReplyGoesOut() throws {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: event("PreToolUse", mode: .decide, id: id) { $0.toolName = "AskUserQuestion"; $0.toolInput = twoQuestions },
                   settings: .default, now: t0)
    let pending = try #require(book.sessions["claude:s1"]?.pending)
    #expect(pending.questions.count == 2)
    #expect(pending.currentQuestion?.index == 0)
    #expect(pending.currentQuestion?.prompt.multiSelect == true)
    #expect(book.recordAnswer(requestId: id, answer: "Freigabe, Fertig") == nil)
    #expect(book.sessions["claude:s1"]?.pending?.currentQuestion?.prompt.question == "Wie lange?")
    let answers = book.recordAnswer(requestId: id, answer: "Kurz")
    #expect(answers == ["Welche Signale?": "Freigabe, Fertig", "Wie lange?": "Kurz"])
}

@Test func multiSelectAnswerJoinsChoicesInOrder() {
    let content = SignalContent(agent: .claude, title: "t", subtitle: "Welche?", kind: .question(options: ["A", "B", "C"]),
                                multiSelect: true)
    #expect(content.multiSelectAnswer(selected: ["C", "A"], typed: "") == .answer("A, C"))
    #expect(content.multiSelectAnswer(selected: ["B"], typed: " und D ") == .answer("B, und D"))
    #expect(content.multiSelectAnswer(selected: [], typed: "  ") == nil)
}

@Test func nextQuestionStartsWithEmptyDraftAndSelection() {
    var signals = SignalLifecycle()
    let id = UUID()
    let first = SignalContent(id: id, agent: .claude, title: "t", subtitle: "1", kind: .question(options: ["A"]),
                              progress: "1/2", multiSelect: true)
    signals.raise(first, now: .now)
    signals.setDraft("Text", for: id)
    signals.toggle("A", for: id)
    #expect(signals.selection(for: id) == ["A"])
    signals.raise(first, now: .now)
    #expect(signals.draft(for: id) == "Text")
    var second = first
    second.progress = "2/2"
    signals.raise(second, now: .now)
    #expect(signals.draft(for: id) == "")
    #expect(signals.selection(for: id).isEmpty)
}

// MARK: - Im Terminal entschieden (#12)

@Test func requestAnsweredElsewhereIsReleased() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: event("PermissionRequest", mode: .decide, id: id) {
        $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("sleep 30")])
    }, settings: .default, now: t0)
    let changes = book.answeredElsewhere(requestId: id)
    #expect(changes == [.clear(sessionKey: "claude:s1"), .release(requestId: id)])
    #expect(book.sessions["claude:s1"]?.pending == nil)
    #expect(book.sessions["claude:s1"]?.status == .working)
}

// MARK: - Form der Signale (#21, #23)

@Test func openingAPanelFromASignal() {
    var state = NotchState()
    state.apply(.signalRaised, style: .banner)
    state.apply(.openPanel(.sessions), style: .banner)
    #expect(state.mode == .panel(.sessions))
    state.apply(.hoverEnded, style: .banner)
    #expect(state.mode == .signal(.banner))
}

@Test func compactVerticalIsShorter() throws {
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 32, leftAuxWidth: 656, rightAuxWidth: 656)
    let full = try #require(NotchGeometry.frame(for: .vertical, screen: screen, islandSideWidth: 120))
    let compact = try #require(NotchGeometry.frame(for: .verticalCompact, screen: screen, islandSideWidth: 120))
    #expect(compact.width == full.width)
    #expect(compact.height == 32 + NotchGeometry.verticalCompactExtraHeight)
    #expect(compact.maxY == full.maxY)
}

// MARK: - Beobachtungen vom Mac (#14)

@Test func subagentStopNeverBecomesTheLastStep() {
    // Etwa 2 s nach jedem `Stop` kommt ein `SubagentStop`, dessen `last_assistant_message` ein vorgeschlagener
    // nächster Prompt des Nutzers ist, nicht die Antwort des Agenten.
    var book = SessionBook()
    _ = book.apply(envelope: event("Stop") { $0.lastAssistantMessage = "Alles erledigt" }, settings: .default, now: t0)
    let changes = book.apply(envelope: event("SubagentStop") { $0.lastAssistantMessage = "ja fang mit 1 und 2 an" },
                             settings: .default, now: t0.addingTimeInterval(2))
    #expect(changes.isEmpty)
    #expect(book.sessions["claude:s1"]?.status == .done)
    #expect(book.sessions["claude:s1"]?.lastStep == "Fertig: Alles erledigt")
}

// MARK: - Hintergrund- und Unteragenten aus der Claude-App (#27, #28)

@Test func taskNotificationIsNoNewTurn() {
    // Ein fertiger Hintergrund-Agent kommt als `UserPromptSubmit` mitten im Turn.
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "los" }, settings: .default, now: t0)
    _ = book.apply(envelope: event("PostToolUseFailure") { $0.toolName = "Bash"; $0.error = "Exit code 1" }, settings: .default, now: t0)
    _ = book.apply(envelope: event("PermissionRequest", mode: .decide, id: id) {
        $0.toolName = "Write"; $0.toolInput = .object(["file_path": .string("/tmp/x.txt")])
    }, settings: .default, now: t0)
    let changes = book.apply(envelope: event("UserPromptSubmit") { $0.prompt = "<task-notification>\n<task-id>a1</task-id>" },
                             settings: .default, now: t0.addingTimeInterval(5))
    #expect(changes.isEmpty)
    let s = book.sessions["claude:s1"]
    #expect(s?.pending?.requestId == id)
    #expect(s?.status == .waitingApproval)
    #expect(s?.errorCount == 1)
    #expect(book.visibleSessions(settings: .default, now: t0.addingTimeInterval(5)).first?.title == "los")
}

@Test func subagentStepsStayOutOfTheMainSession() {
    var book = SessionBook()
    _ = book.apply(envelope: event("PreToolUse") { $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("npm test")]) },
                   settings: .default, now: t0)
    _ = book.apply(envelope: event("SubagentStart") { $0.agentId = "a1"; $0.agentType = "Explore" }, settings: .default, now: t0)
    _ = book.apply(envelope: event("PreToolUse") {
        $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("sleep 4")]); $0.agentId = "a1"; $0.agentType = "Explore"
    }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.lastStep == "Führt aus: npm test")
    #expect(book.sessions["claude:s1"]?.runningSubagents == 1)
    let id = UUID()
    _ = book.apply(envelope: event("PermissionRequest", mode: .decide, id: id) {
        $0.toolName = "Bash"; $0.toolInput = .object(["command": .string("rm x")]); $0.agentId = "a1"; $0.agentType = "Explore"
    }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.pending?.subagent == "Explore")
    // Ein `SubagentStop` ohne bekannte ID (Prompt-Vorschläge nach jedem `Stop`) zählt nicht.
    _ = book.apply(envelope: event("SubagentStop") { $0.agentId = "zz" }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.runningSubagents == 1)
    _ = book.apply(envelope: event("SubagentStop") { $0.agentId = "a1" }, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.runningSubagents == 0)
}

@Test func subagentFieldsAreDecoded() throws {
    let json = #"{"hook_event_name":"PreToolUse","session_id":"s1","agent_id":"a1","agent_type":"Explore"}"#
    let e = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(e.agentId == "a1")
    #expect(e.agentType == "Explore")
}
