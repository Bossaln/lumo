import Foundation
import Testing
@testable import NotchaiCore

private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

/// 20.10.2026, 12:00 Uhr in Berlin.
private let noon = isoDate("2026-10-20T10:00:00.000Z")

private func at(_ minutes: Double) -> Date { noon.addingTimeInterval(minutes * 60) }

private func summary(_ configure: (inout TranscriptSummary) -> Void) -> TranscriptSummary {
    var s = TranscriptSummary(agent: .claude)
    configure(&s)
    return s
}

@Test func countsOnlyToday() {
    let s = summary {
        // 23:30 am Vortag (Berliner Zeit) zählt nicht, 00:30 heute schon.
        $0.prompts = [isoDate("2026-10-19T21:30:00.000Z"), isoDate("2026-10-19T22:30:00.000Z"), at(0)]
        $0.turns = [TurnSpan(start: isoDate("2026-10-19T21:30:00.000Z"), end: isoDate("2026-10-19T21:50:00.000Z")),
                    TurnSpan(start: at(0), end: at(12.5))]
        $0.editedFiles = [EditedFile(path: "/a/gestern.swift", at: isoDate("2026-10-19T21:40:00.000Z")),
                          EditedFile(path: "/a/heute.swift", at: at(5))]
    }
    let stats = DailyStatsCalculator.compute([s], day: noon, calendar: berlin, now: at(60))
    #expect(stats == DailyStats(tasks: 2, minutes: 12, files: 1))
}

@Test func openTurnCountsUntilNow() {
    let s = summary {
        $0.prompts = [at(0)]
        $0.turns = [TurnSpan(start: at(0), end: nil)]
        $0.turnInProgress = true
        $0.lastActivity = at(29)
    }
    #expect(DailyStatsCalculator.compute([s], day: noon, calendar: berlin, now: at(30)).minutes == 30)
}

@Test func abandonedOpenTurnStopsCountingAfterSilence() {
    // Ein Turn, der nie sauber endete (Absturz), zählt nur bis kurz nach dem letzten Lebenszeichen.
    let s = summary {
        $0.turns = [TurnSpan(start: at(0), end: nil)]
        $0.turnInProgress = true
        $0.lastActivity = at(5)
    }
    #expect(DailyStatsCalculator.compute([s], day: noon, calendar: berlin, now: at(300)).minutes == 15)
}

@Test func filesAreDistinctAcrossSessions() {
    let a = summary { $0.editedFiles = [EditedFile(path: "/p/x.swift", at: at(1)), EditedFile(path: "/p/x.swift", at: at(2)),
                                        EditedFile(path: "/p/y.swift", at: at(3))] }
    var b = summary { $0.editedFiles = [EditedFile(path: "/p/y.swift", at: at(4)), EditedFile(path: "/p/z.swift", at: at(5))] }
    b.agent = .codex
    #expect(DailyStatsCalculator.compute([a, b], day: noon, calendar: berlin, now: at(10)).files == 3)
}

@Test func singularForms() {
    #expect(DailyStats(tasks: 10, minutes: 54, files: 14).formatted() == "Heute: 10 Aufgaben · 54 min · 14 Dateien")
    #expect(DailyStats(tasks: 1, minutes: 1, files: 1).formatted() == "Heute: 1 Aufgabe · 1 min · 1 Datei")
    #expect(DailyStats(tasks: 0, minutes: 0, files: 0).formatted() == "Heute: 0 Aufgaben · 0 min · 0 Dateien")
}
