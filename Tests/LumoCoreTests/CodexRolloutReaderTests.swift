import Foundation
import Testing
@testable import LumoCore

private func readCodex(_ lines: [Data]) -> TranscriptSummary {
    var reader = CodexRolloutReader()
    for line in lines { reader.consume(line: line) }
    return reader.summary
}

@Test func readsMetaAndModel() throws {
    let s = readCodex(try fixtureLines("codex-basic"))
    #expect(s.agent == .codex)
    #expect(s.sessionId == "019a0000-c0de-7000-8000-000000000001")
    #expect(s.cwd == "/Users/test/Developer/lumo")
    #expect(s.originator == "codex_tui")
    #expect(s.model == "gpt-6.1-sol")
    #expect(s.lastActivity == isoDate("2026-10-20T11:00:10.100Z"))
}

@Test func tokenCountGivesContext() throws {
    let s = readCodex(try fixtureLines("codex-basic"))
    // Das spätere `token_count` ohne `info` (nur Limits) ändert nichts.
    #expect(s.contextTokens == 22168)
    #expect(s.contextWindow == 258400)
}

@Test func taskCompleteEndsTurn() throws {
    let lines = try fixtureLines("codex-basic")
    let running = readCodex(Array(lines.prefix(8)))
    #expect(running.turnInProgress)
    #expect(running.turns == [TurnSpan(start: isoDate("2026-10-20T11:00:00.010Z"), end: nil)])
    let s = readCodex(lines)
    #expect(s.turnInProgress == false)
    #expect(s.lastFinishedAt == isoDate("2026-10-20T11:00:10.100Z"))
    #expect(s.lastAssistantText == "Test repariert.")
    #expect(s.turns == [TurnSpan(start: isoDate("2026-10-20T11:00:00.010Z"), end: isoDate("2026-10-20T11:00:10.100Z"))])
}

@Test func applyPatchCollectsFiles() throws {
    let s = readCodex(try fixtureLines("codex-basic"))
    // Relative Pfade gelten im Arbeitsordner der Session.
    #expect(s.editedFiles == [
        EditedFile(path: "/Users/test/Developer/lumo/Sources/A.swift", at: isoDate("2026-10-20T11:00:08.000Z")),
        EditedFile(path: "/Users/test/Developer/lumo/Tests/B.swift", at: isoDate("2026-10-20T11:00:08.000Z")),
    ])
    #expect(s.lastStep == "Bearbeitet A.swift")
}

@Test func functionCallArgumentsAreDecoded() throws {
    let s = readCodex(Array(try fixtureLines("codex-basic").prefix(7)))
    #expect(s.lastStep == "Führt aus: swift test --filter Notch")
}

@Test func environmentContextIsNotAPrompt() throws {
    let s = readCodex(try fixtureLines("codex-basic"))
    #expect(s.prompts == [isoDate("2026-10-20T11:00:00.050Z")])
    #expect(s.firstPrompt == "Repariere den Test")
    #expect(s.lastPrompt == "Repariere den Test")
}

@Test func indexLaterLineWins() throws {
    let titles = CodexSessionIndex.titles(from: try fixtureLines("codex-index"))
    #expect(titles == [
        "019a0000-c0de-7000-8000-000000000001": "Notch-Test reparieren",
        "019a0000-c0de-7000-8000-000000000002": "Anderes Projekt",
    ])
}
