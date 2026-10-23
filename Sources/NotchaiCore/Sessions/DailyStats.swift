import Foundation

/// Fußzeile der Session-Liste: „Heute: 10 Aufgaben · 54 min · 14 Dateien“.
public struct DailyStats: Equatable, Sendable {
    public var tasks: Int
    public var minutes: Int
    public var files: Int

    public init(tasks: Int, minutes: Int, files: Int) {
        self.tasks = tasks
        self.minutes = minutes
        self.files = files
    }

    public func formatted() -> String {
        let taskWord = tasks == 1 ? "Aufgabe" : "Aufgaben"
        let fileWord = files == 1 ? "Datei" : "Dateien"
        return "Heute: \(tasks) \(taskWord) · \(minutes) min · \(files) \(fileWord)"
    }
}

public enum DailyStatsCalculator {
    /// Ein offener Turn zählt höchstens so lange über das letzte Lebenszeichen hinaus. Sonst liefe ein
    /// abgestürzter Turn den ganzen Tag weiter.
    static let openTurnSilence: TimeInterval = 10 * 60

    /// Prompts, Turn-Minuten (Turns, die an `day` beginnen) und verschiedene geänderte Dateien eines Tages.
    public static func compute(_ summaries: [TranscriptSummary], day: Date, calendar: Calendar, now: Date) -> DailyStats {
        func isToday(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: day) }
        var tasks = 0
        var seconds: TimeInterval = 0
        var files = Set<String>()
        for summary in summaries {
            tasks += summary.prompts.filter(isToday).count
            for turn in summary.turns where isToday(turn.start) {
                let end = turn.end ?? min(now, max(summary.lastActivity ?? turn.start, turn.start).addingTimeInterval(openTurnSilence))
                seconds += max(0, end.timeIntervalSince(turn.start))
            }
            files.formUnion(summary.editedFiles.filter { isToday($0.at) }.map(\.path))
        }
        return DailyStats(tasks: tasks, minutes: Int(seconds / 60), files: files.count)
    }
}
