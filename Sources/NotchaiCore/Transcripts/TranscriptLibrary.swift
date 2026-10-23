import Foundation

/// Findet die Transkripte laufender Sessions und liest sie inkrementell:
/// `~/.claude/projects/<projekt>/<session>.jsonl` und `~/.codex/sessions/<jahr>/<monat>/<tag>/*.jsonl`.
/// Gezählt werden nur Dateien, die innerhalb von `maxAgeHours` geändert wurden. Codex-Titel kommen aus
/// `~/.codex/session_index.jsonl`. Nicht threadsicher: gehört einer seriellen Warteschlange (`SessionMonitor`).
public final class TranscriptLibrary {
    /// So oft werden die Ordner neu durchsucht; dazwischen werden nur die bekannten Dateien gelesen.
    static let discoveryInterval: TimeInterval = 10
    /// Codex legt ein Rollout im Ordner seines Starttags ab; so viele Tage zurück wird gesucht.
    static let codexDays = 7

    private enum Reader {
        case claude(ClaudeTranscriptReader)
        case codex(CodexRolloutReader)

        var summary: TranscriptSummary {
            switch self {
            case .claude(let r): r.summary
            case .codex(let r): r.summary
            }
        }

        mutating func consume(_ line: Data) {
            switch self {
            case .claude(var r):
                r.consume(line: line)
                self = .claude(r)
            case .codex(var r):
                r.consume(line: line)
                self = .codex(r)
            }
        }

        func fresh() -> Reader {
            switch self {
            case .claude: .claude(ClaudeTranscriptReader())
            case .codex: .codex(CodexRolloutReader())
            }
        }
    }

    private let home: URL
    private let tailer = TranscriptTailer()
    private var readers: [URL: Reader] = [:]
    private var lastDiscovery: Date?
    private var codexTitles: [String: String] = [:]
    private var indexModified: Date?

    /// Letzte Zusammenfassung je Datei (auch für die Tagesbilanz).
    public var summaries: [TranscriptSummary] {
        readers.values.map { withTitle($0.summary) }
    }

    public init(home: URL) {
        self.home = home
    }

    /// Liest Neues ein und gibt die Zusammenfassungen zurück, die sich dabei geändert haben.
    public func poll(now: Date, maxAgeHours: Int, calendar: Calendar) -> [TranscriptSummary] {
        let oldest = now.addingTimeInterval(-TimeInterval(maxAgeHours) * 3600)
        if lastDiscovery.map({ now.timeIntervalSince($0) >= Self.discoveryInterval || now < $0 }) ?? true {
            discover(now: now, oldest: oldest, calendar: calendar)
            lastDiscovery = now
        }
        let titlesChanged = refreshCodexTitles()
        var changed: [TranscriptSummary] = []
        for url in readers.keys.sorted(by: { $0.path < $1.path }) {
            guard var reader = readers[url] else { continue }
            let lines = tailer.readNewLines(at: url)
            if tailer.wasRestarted(url) { reader = reader.fresh() }
            for line in lines { reader.consume(line) }
            readers[url] = reader
            let isCodex = if case .codex = reader { true } else { false }
            if !lines.isEmpty || (titlesChanged && isCodex) {
                changed.append(withTitle(reader.summary))
            }
        }
        return changed.filter { $0.sessionId != nil }
    }

    // MARK: - Dateien finden

    private func discover(now: Date, oldest: Date, calendar: Calendar) {
        var found: [URL: Reader] = [:]
        let projects = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        for folder in contents(of: projects) {
            for file in contents(of: folder) where file.pathExtension == "jsonl" {
                found[file] = .claude(ClaudeTranscriptReader())
            }
        }
        let sessions = home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        for daysBack in 0..<Self.codexDays {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { continue }
            let folder = sessions.appending(path: String(format: "%04d/%02d/%02d", year, month, dayNumber), directoryHint: .isDirectory)
            for file in contents(of: folder) where file.pathExtension == "jsonl" {
                found[file] = .codex(CodexRolloutReader())
            }
        }
        let recent = found.filter { modified($0.key).map { $0 >= oldest } ?? false }
        // Bekannte Dateien behalten ihren Lesestand; zu alt gewordene werden vergessen.
        for url in readers.keys where recent[url] == nil { tailer.forget(url) }
        readers = recent.mapValues { $0 }.reduce(into: [:]) { result, entry in
            result[entry.key] = readers[entry.key] ?? entry.value
        }
    }

    private func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    private func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - Codex-Titel

    /// Liest den Index neu, wenn er sich geändert hat; `true`, wenn sich Titel geändert haben.
    private func refreshCodexTitles() -> Bool {
        let index = home.appending(path: ".codex/session_index.jsonl")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: index.path))?[.modificationDate] as? Date
        guard stamp != indexModified else { return false }
        indexModified = stamp
        let lines = ((try? Data(contentsOf: index)) ?? Data()).split(separator: UInt8(ascii: "\n")).map { Data($0) }
        let titles = CodexSessionIndex.titles(from: lines)
        defer { codexTitles = titles }
        return titles != codexTitles
    }

    private func withTitle(_ summary: TranscriptSummary) -> TranscriptSummary {
        guard summary.agent == .codex, let id = summary.sessionId, let title = codexTitles[id] else { return summary }
        var s = summary
        s.customTitle = title
        return s
    }
}
