import Foundation
import Testing
@testable import LumoCore

/// Liest eine synthetische Test-Datei aus `Fixtures/` Zeile für Zeile.
func fixtureLines(_ name: String) throws -> [Data] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    return try Data(contentsOf: url).split(separator: UInt8(ascii: "\n")).map { Data($0) }
}

func isoDate(_ text: String) -> Date {
    try! Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

private func readClaude(_ name: String) throws -> TranscriptSummary {
    var reader = ClaudeTranscriptReader()
    for line in try fixtureLines(name) { reader.consume(line: line) }
    return reader.summary
}

@Test func readsIdentityAndTitle() throws {
    let s = try readClaude("claude-basic")
    #expect(s.agent == .claude)
    #expect(s.sessionId == "sess-basic")
    #expect(s.cwd == "/Users/test/Developer/lumo")
    #expect(s.entrypoint == "claude-desktop")
    #expect(s.customTitle == "Notch-Form bauen")
    #expect(s.model == "claude-opus-5-5")
    #expect(s.lastActivity == isoDate("2026-10-20T09:10:05.000Z"))
}

@Test func promptsSkipMetaAndToolResults() throws {
    let s = try readClaude("claude-basic")
    #expect(s.prompts == [isoDate("2026-10-20T09:00:00.000Z"), isoDate("2026-10-20T09:10:00.000Z")])
    #expect(s.firstPrompt == "Baue die Notch-Form")
    #expect(s.lastPrompt == "Jetzt die Farben")
}

@Test func contextTokensSumThreeFields() throws {
    var reader = ClaudeTranscriptReader()
    for line in try fixtureLines("claude-basic").prefix(3) { reader.consume(line: line) }
    #expect(reader.summary.contextTokens == 2 + 47864 + 43151)
    // Danach zählt immer die letzte Antwort.
    #expect(try readClaude("claude-basic").contextTokens == 10 + 1000 + 120_000)
}

@Test func endTurnClosesTurn() throws {
    var reader = ClaudeTranscriptReader()
    for line in try fixtureLines("claude-basic").prefix(5) { reader.consume(line: line) }
    #expect(reader.summary.turnInProgress == false)
    #expect(reader.summary.lastFinishedAt == isoDate("2026-10-20T09:00:10.000Z"))
    #expect(reader.summary.lastAssistantText == "Erledigt.\nDie Form steht.")
    #expect(reader.summary.turns == [TurnSpan(start: isoDate("2026-10-20T09:00:00.000Z"), end: isoDate("2026-10-20T09:00:10.000Z"))])
    // Der zweite Prompt öffnet einen neuen Turn, der noch läuft.
    let s = try readClaude("claude-basic")
    #expect(s.turnInProgress)
    #expect(s.turns.last == TurnSpan(start: isoDate("2026-10-20T09:10:00.000Z"), end: nil))
}

@Test func toolUseSetsLastStepAndEditedFiles() throws {
    let s = try readClaude("claude-basic")
    #expect(s.lastStep == "Bearbeitet NotchShape.swift")
    #expect(s.editedFiles == [EditedFile(path: "/Users/test/Developer/lumo/Sources/Lumo/Notch/NotchShape.swift",
                                         at: isoDate("2026-10-20T09:10:05.000Z"))])
}

@Test func toolErrorCounts() throws {
    let s = try readClaude("claude-tools")
    #expect(s.errorCount == 1)
    #expect(s.editedFiles.map(\.path) == ["/tmp/x/a.swift", "/tmp/x/b.swift"])
}

@Test func sidechainAndRequestBlobsAreIgnored() throws {
    // Unteragenten und mitgeschriebene API-Anfragen zählen weder als Prompt noch als Schritt oder Fehler.
    let s = try readClaude("claude-tools")
    #expect(s.prompts.count == 1)
    #expect(s.lastStep == "Bearbeitet b.swift")
    #expect(s.contextTokens == 2 + 47864 + 43151)
}

@Test func syntheticModelDoesNotReplaceTheRealOne() throws {
    let s = try readClaude("claude-tools")
    #expect(s.model == "claude-opus-5-5")
    #expect(s.lastAssistantText == "Fertig mit zwei Dateien.")
    #expect(s.turnInProgress == false)
}

@Test func garbageLineIsIgnored() {
    var reader = ClaudeTranscriptReader()
    reader.consume(line: Data("{kaputt".utf8))
    reader.consume(line: Data("[1,2]".utf8))
    reader.consume(line: Data())
    #expect(reader.summary == TranscriptSummary(agent: .claude))
}
