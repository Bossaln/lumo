import Foundation
import Testing
@testable import NotchaiCore

private let t0 = Date(timeIntervalSince1970: 1_792_900_000)

private func hook(_ name: String, session: String = "s1", agent: AgentKind = .claude, pid: Int32? = nil,
                  mode: HookMode = .event, tool: String? = nil, id: UUID = UUID()) -> HookEnvelope {
    var event = HookEvent(hookEventName: name, sessionId: session)
    event.cwd = "/Users/test/Developer/notchai"
    event.toolName = tool
    return HookEnvelope(requestId: id, agent: agent, mode: mode, event: event, env: [:], sentAt: t0, agentPid: pid)
}

private func transcript(session: String = "s1", at date: Date) -> TranscriptSummary {
    var s = TranscriptSummary(agent: .claude)
    s.sessionId = session
    s.cwd = "/Users/test/Developer/notchai"
    s.lastActivity = date
    return s
}

private func visible(_ book: SessionBook, at date: Date) -> [String] {
    book.visibleSessions(settings: .default, now: date).map(\.sessionId)
}

// MARK: - Agent-Prozess

private let tree: [Int32: (parent: Int32, name: String)] = [
    500: (400, "sh"), 400: (300, "claude"), 300: (200, "zsh"), 200: (1, "Terminal"),
    610: (600, "bash"), 600: (1, "codex"),
]

@Test func hookFindsItsAgentAboveTheShell() {
    #expect(ProcessTree.agent(above: 500) { tree[$0] } == 400)
    // Ohne Shell dazwischen ist der Elternprozess selbst der Agent.
    #expect(ProcessTree.agent(above: 400) { tree[$0] } == 400)
    #expect(ProcessTree.agent(above: 610) { tree[$0] } == 600)
    #expect(ProcessTree.agent(above: 999) { tree[$0] } == nil)
    #expect(ProcessTree.agent(above: 7) { _ in (7, "sh") } == nil)
}

@Test func envelopeCarriesTheAgentProcess() throws {
    let sent = hook("SessionStart", pid: 4242)
    let decoded = try JSONDecoder().decode(HookEnvelope.self, from: JSONEncoder().encode(sent))
    #expect(decoded.agentPid == 4242)
    // Ältere Hook-Programme schicken keine Prozessnummer.
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sent)) as? [String: Any])
    json["agentPid"] = nil
    let old = try JSONDecoder().decode(HookEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.agentPid == nil)
}

// MARK: - Nur aktive Sessions

@Test func closedAgentRemovesItsSession() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: hook("SessionStart", pid: 4242), settings: .default, now: t0)
    _ = book.apply(envelope: hook("PermissionRequest", pid: 4242, mode: .decide, tool: "Bash", id: id),
                   settings: .default, now: t0)
    _ = book.apply(envelope: hook("SessionStart", session: "s2", pid: 5000), settings: .default, now: t0)
    // Terminal zu, ohne dass `SessionEnd` kam: Der Prozess ist weg.
    let changes = book.removeEnded { $0 != 4242 }
    #expect(book.sessions["claude:s1"] == nil)
    #expect(book.sessions["claude:s2"] != nil)
    #expect(changes.contains(.release(requestId: id)))
}

@Test func runningAgentKeepsAnIdleSessionVisible() {
    var book = SessionBook()
    _ = book.apply(envelope: hook("Stop", pid: 4242), settings: .default, now: t0)
    _ = book.removeEnded { _ in true }
    #expect(visible(book, at: t0.addingTimeInterval(3 * 3600)) == ["s1"])
}

@Test func sessionWithoutKnownProcessFadesAfterHalfAnHour() {
    var book = SessionBook()
    _ = book.apply(summary: transcript(at: t0), settings: .default, now: t0)
    #expect(visible(book, at: t0.addingTimeInterval(20 * 60)) == ["s1"])
    #expect(visible(book, at: t0.addingTimeInterval(31 * 60)).isEmpty)
    // Neue Zeilen im Transkript holen sie zurück.
    _ = book.apply(summary: transcript(at: t0.addingTimeInterval(40 * 60)), settings: .default, now: t0.addingTimeInterval(40 * 60))
    #expect(visible(book, at: t0.addingTimeInterval(41 * 60)) == ["s1"])
}

@Test func appThreadsSharingOneProcessFadeWhenIdle() {
    // Die Codex-App führt alle Threads über einen Prozess: Er läuft, solange die App offen ist, auch für Threads,
    // die niemand mehr benutzt.
    var book = SessionBook()
    _ = book.apply(envelope: hook("Stop", session: "t1", agent: .codex, pid: 777), settings: .default, now: t0)
    _ = book.apply(envelope: hook("Stop", session: "t2", agent: .codex, pid: 777), settings: .default, now: t0)
    _ = book.removeEnded { _ in true }
    #expect(visible(book, at: t0.addingTimeInterval(20 * 60)).sorted() == ["t1", "t2"])
    #expect(visible(book, at: t0.addingTimeInterval(31 * 60)).isEmpty)
}

@Test func sessionInTheClaudeAppFadesWhenIdle() {
    // Ob ein Chat in der App noch offen ist, verrät kein Prozess.
    var event = HookEvent(hookEventName: "Stop", sessionId: "s1")
    event.cwd = "/Users/test/Developer/notchai"
    let envelope = HookEnvelope(requestId: UUID(), agent: .claude, mode: .event, event: event,
                                env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], sentAt: t0, agentPid: 4242)
    var book = SessionBook()
    _ = book.apply(envelope: envelope, settings: .default, now: t0)
    #expect(visible(book, at: t0.addingTimeInterval(20 * 60)) == ["s1"])
    #expect(visible(book, at: t0.addingTimeInterval(31 * 60)).isEmpty)
}

// MARK: - Von Hand entfernen

@Test func removedSessionStaysHiddenUntilItDoesSomething() {
    var book = SessionBook()
    _ = book.apply(envelope: hook("Stop", pid: 4242), settings: .default, now: t0)
    _ = book.dismiss("claude:s1", now: t0.addingTimeInterval(60))
    #expect(visible(book, at: t0.addingTimeInterval(120)).isEmpty)
    _ = book.apply(envelope: hook("UserPromptSubmit", pid: 4242), settings: .default, now: t0.addingTimeInterval(180))
    #expect(visible(book, at: t0.addingTimeInterval(181)) == ["s1"])
}

@Test func removingAWaitingSessionReleasesItsRequest() {
    var book = SessionBook()
    let id = UUID()
    _ = book.apply(envelope: hook("PermissionRequest", pid: 4242, mode: .decide, tool: "Bash", id: id),
                   settings: .default, now: t0)
    let changes = book.dismiss("claude:s1", now: t0.addingTimeInterval(5))
    #expect(changes.contains(.release(requestId: id)))
    #expect(book.pendingRequests().isEmpty)
}
