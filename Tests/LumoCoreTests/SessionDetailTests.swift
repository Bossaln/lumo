import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_900_000)

private func rollout(_ rows: [String]) -> TranscriptSummary {
    var reader = CodexRolloutReader()
    for row in rows { reader.consume(line: Data(row.utf8)) }
    return reader.summary
}

private let meta = #"{"timestamp":"2026-10-20T11:00:00.000Z","type":"session_meta","payload":{"id":"c1","cwd":"/Users/test/Developer/lumo","originator":"codex_tui"}}"#

private func tokenCount(at time: String, limits: String) -> String {
    #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(limits)}}"#
}

// MARK: - Nutzungslimits (Codex)

@Test func codexRolloutReadsUsageLimits() throws {
    let summary = rollout([meta, tokenCount(at: "2026-10-20T11:00:05.000Z", limits: #"""
        {"limit_id":"codex","primary":{"used_percent":23.5,"window_minutes":300,"resets_at":1792903600},
         "secondary":{"used_percent":8,"window_minutes":10080,"resets_at":1793400000},"plan_type":"plus"}
        """#.replacingOccurrences(of: "\n", with: ""))])
    let limits = try #require(summary.usageLimits)
    #expect(limits.primary == UsageWindow(usedPercent: 23.5, windowMinutes: 300,
                                          resetsAt: Date(timeIntervalSince1970: 1_792_903_600)))
    #expect(limits.secondary?.usedPercent == 8)
    #expect(limits.secondary?.windowMinutes == 10080)
    #expect(limits.plan == "plus")
}

@Test func olderCodexCountsTheResetFromTheEvent() throws {
    let summary = rollout([meta, tokenCount(at: "2026-10-20T11:00:05.000Z",
                                            limits: #"{"primary":{"used_percent":40,"window_minutes":300,"resets_in_seconds":600}}"#)])
    let reset = try #require(summary.usageLimits?.primary?.resetsAt)
    #expect(reset == TranscriptDate.parse("2026-10-20T11:10:05.000Z"))
    #expect(summary.usageLimits?.secondary == nil)
}

@Test func emptyOrForeignLimitsKeepTheKnownOnes() {
    let summary = rollout([
        meta,
        tokenCount(at: "2026-10-20T11:00:05.000Z", limits: #"{"limit_id":"codex","primary":{"used_percent":12,"window_minutes":300}}"#),
        // Ohne Fenster sagt die Meldung nichts Neues.
        tokenCount(at: "2026-10-20T11:00:06.000Z", limits: #"{"limit_id":"codex"}"#),
        tokenCount(at: "2026-10-20T11:00:07.000Z", limits: "null"),
        // Limits eines anderen Modells gehören nicht zur Session.
        tokenCount(at: "2026-10-20T11:00:08.000Z", limits: #"{"limit_id":"codex_other","primary":{"used_percent":99}}"#),
    ])
    #expect(summary.usageLimits?.primary?.usedPercent == 12)
}

// MARK: - Was die Detailansicht zeigt

@Test func sessionCarriesModelContextAndLimits() throws {
    var claude = TranscriptSummary(agent: .claude)
    claude.sessionId = "s1"
    claude.model = "claude-sonnet-4-5"
    claude.contextTokens = 84_000
    claude.lastActivity = t0
    var codex = TranscriptSummary(agent: .codex)
    codex.sessionId = "c1"
    codex.model = "gpt-5.5-codex"
    codex.contextTokens = 50_000
    codex.contextWindow = 258_400
    codex.usageLimits = UsageLimits(primary: UsageWindow(usedPercent: 30, windowMinutes: 300, resetsAt: nil))
    codex.lastActivity = t0

    var book = SessionBook()
    _ = book.apply(summary: claude, settings: .default, now: t0)
    _ = book.apply(summary: codex, settings: .default, now: t0)
    let s1 = try #require(book.sessions["claude:s1"])
    #expect(s1.model == "claude-sonnet-4-5")
    #expect(s1.contextTokens == 84_000)
    #expect(s1.contextLimit == 200_000)
    #expect(s1.usageLimits == nil)
    let c1 = try #require(book.sessions["codex:c1"])
    #expect(c1.contextLimit == 258_400)
    #expect(c1.usageLimits?.primary?.usedPercent == 30)

    // Spätere Zeilen ohne Limits löschen die bekannten nicht.
    codex.usageLimits = nil
    _ = book.apply(summary: codex, settings: .default, now: t0)
    #expect(book.sessions["codex:c1"]?.usageLimits?.primary?.usedPercent == 30)
}

@Test func hookTellsTheModelBeforeTheTranscriptDoes() {
    var event = HookEvent(hookEventName: "SessionStart", sessionId: "s1")
    event.transcriptPath = "/Users/test/.claude/projects/lumo/x.jsonl"
    event.model = "claude-opus-5-5"
    let envelope = HookEnvelope(requestId: UUID(), agent: .claude, mode: .event, event: event, env: [:], sentAt: t0)
    var book = SessionBook()
    _ = book.apply(envelope: envelope, settings: .default, now: t0)
    #expect(book.sessions["claude:s1"]?.model == "claude-opus-5-5")
}

@Test func sessionCountsPromptsAndEditedFiles() throws {
    var summary = TranscriptSummary(agent: .claude)
    summary.sessionId = "s1"
    summary.lastActivity = t0.addingTimeInterval(600)
    summary.prompts = [t0, t0.addingTimeInterval(120), t0.addingTimeInterval(300)]
    summary.turns = [TurnSpan(start: t0, end: t0.addingTimeInterval(60))]
    summary.editedFiles = [EditedFile(path: "/a.swift", at: t0), EditedFile(path: "/b.swift", at: t0),
                           EditedFile(path: "/a.swift", at: t0.addingTimeInterval(200))]
    var book = SessionBook()
    _ = book.apply(summary: summary, settings: .default, now: t0)
    let session = try #require(book.sessions["claude:s1"])
    #expect(session.promptCount == 3)
    #expect(session.editedFileCount == 2)
    #expect(session.startedAt == t0)
}

// MARK: - Wo die Session läuft

@Test func hostNamesWhereTheSessionRuns() {
    #expect(SessionHost(entrypoint: "claude-desktop").source == .claudeApp)
    #expect(SessionHost(bundleId: "com.anthropic.claudefordesktop").source == .claudeApp)
    #expect(SessionHost(bundleId: "com.openai.codex").source == .codexApp)
    #expect(SessionHost(originator: "Codex Desktop").source == .codexApp)
    #expect(SessionHost(originator: "codex_vscode").source == .vscode)
    #expect(SessionHost(entrypoint: "claude-vscode").source == .vscode)
    #expect(SessionHost(entrypoint: "cli", bundleId: "com.todesktop.230313mzl4w4u92").source == .cursor)
    #expect(SessionHost(entrypoint: "cli", termProgram: "vscode").source == .vscode)
    #expect(SessionHost(entrypoint: "cli", cmuxSurface: "surface-1").source == .cmux)
    #expect(SessionHost(entrypoint: "cli", termProgram: "iTerm.app").source == .terminal("iTerm"))
    #expect(SessionHost(entrypoint: "cli", termProgram: "Apple_Terminal").source == .terminal("Terminal"))
    #expect(SessionHost(entrypoint: "cli", termProgram: "ghostty").source == .terminal("Ghostty"))
    #expect(SessionHost(originator: "codex_exec").source == .exec)
    #expect(SessionHost(entrypoint: "cli").source == .terminal(nil))
    #expect(SessionHost(originator: "codex_tui").source == .terminal(nil))
    #expect(SessionHost().source == .unknown)
}
