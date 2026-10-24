import Foundation
import Testing
@testable import NotchaiCore

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "notchai-lib-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func copyFixture(_ name: String, to url: URL, modified: Date) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let lines = try fixtureLines(name)
    try lines.map { $0 + Data("\n".utf8) }.reduce(Data(), +).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private let now = isoDate("2026-10-20T12:00:00.000Z")

@Test func findsRecentClaudeAndCodexTranscripts() throws {
    let home = try makeHome()
    try copyFixture("claude-basic", to: home.appending(path: ".claude/projects/-Users-test-notchai/sess-basic.jsonl"), modified: now)
    try copyFixture("claude-tools", to: home.appending(path: ".claude/projects/-tmp-x/alt.jsonl"),
                    modified: now.addingTimeInterval(-30 * 3600))
    try copyFixture("codex-basic", to: home.appending(path: ".codex/sessions/2026/10/20/rollout-a.jsonl"), modified: now)
    try copyFixture("codex-index", to: home.appending(path: ".codex/session_index.jsonl"), modified: now)
    let library = TranscriptLibrary(home: home)
    let changed = library.poll(now: now, maxAgeHours: 24, calendar: utc)
    #expect(Set(changed.compactMap(\.sessionId)) == ["sess-basic", "019a0000-c0de-7000-8000-000000000001"])
    // Codex-Titel kommen aus dem Index.
    #expect(changed.first { $0.agent == .codex }?.customTitle == "Notch-Test reparieren")
    // Nichts Neues: Der nächste Durchlauf meldet nichts.
    #expect(library.poll(now: now, maxAgeHours: 24, calendar: utc).isEmpty)
    #expect(library.summaries.count == 2)
}

@Test func yesterdaysCodexFolderIsWatchedToo() throws {
    let home = try makeHome()
    try copyFixture("codex-basic", to: home.appending(path: ".codex/sessions/2026/10/19/rollout-b.jsonl"),
                    modified: now.addingTimeInterval(-3600))
    let changed = TranscriptLibrary(home: home).poll(now: now, maxAgeHours: 24, calendar: utc)
    #expect(changed.count == 1)
}

@Test func olderCodexThreadContinuedTodayIsFound() throws {
    // Die Codex-App führt alte Threads weiter; Codex schreibt dann in die Datei im Ordner ihres Starttags.
    let home = try makeHome()
    try copyFixture("codex-basic", to: home.appending(path: ".codex/sessions/2026/09/26/rollout-old.jsonl"),
                    modified: now.addingTimeInterval(-600))
    let changed = TranscriptLibrary(home: home).poll(now: now, maxAgeHours: 24, calendar: utc)
    #expect(changed.count == 1)
}

@Test func appendedLinesUpdateTheSummary() throws {
    let home = try makeHome()
    let file = home.appending(path: ".claude/projects/p/s.jsonl")
    try copyFixture("claude-basic", to: file, modified: now)
    let library = TranscriptLibrary(home: home)
    _ = library.poll(now: now, maxAgeHours: 24, calendar: utc)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"type":"assistant","sessionId":"sess-basic","timestamp":"2026-10-20T09:11:00.000Z","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"Fertig"}],"stop_reason":"end_turn"}}"#.utf8) + Data("\n".utf8))
    try handle.close()
    let changed = library.poll(now: now, maxAgeHours: 24, calendar: utc)
    #expect(changed.count == 1)
    #expect(changed.first?.turnInProgress == false)
    #expect(changed.first?.lastAssistantText == "Fertig")
}
