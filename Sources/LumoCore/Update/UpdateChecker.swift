import Foundation

/// Ergebnis eines Shell-Kommandos (stdout und stderr zusammen).
public struct CommandResult: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }

    var succeeded: Bool { status == 0 }
    var trimmed: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Führt ein Kommando in einem Ordner aus. Die App nimmt dafür die Login-Shell des Besitzers,
/// damit Git dieselben Zugangsdaten und Programme findet wie im Terminal.
public protocol CommandRunning: Sendable {
    func run(_ command: String, in directory: String) async -> CommandResult
}

/// Ein verfügbares Update.
public struct UpdateOffer: Equatable, Sendable {
    /// Neue Commits.
    public var count: Int
    /// Ihre Überschriften, neueste zuerst (höchstens 20).
    public var subjects: [String]
    /// Branch, auf dem der Quellordner gerade steht.
    public var branch: String
    /// Woher der neue Stand kommt, etwa `origin/main`.
    public var upstream: String
    /// Gesetzt, wenn der bisherige Branch auf GitHub verschwunden ist (nach dem Mergen) und das Update
    /// deshalb auf diesen Branch wechselt.
    public var switchTo: String?

    public init(count: Int, subjects: [String], branch: String, upstream: String, switchTo: String?) {
        self.count = count
        self.subjects = subjects
        self.branch = branch
        self.upstream = upstream
        self.switchTo = switchTo
    }
}

/// Eine neuere Version auf GitHub (für Builds ohne Quellordner, etwa über Homebrew installiert).
public struct ReleaseOffer: Equatable, Sendable {
    /// Ohne führendes „v“, etwa `0.2.0`.
    public var version: String
    /// Seite der Version auf GitHub.
    public var pageURL: String
    /// Die ersten Punkte der Versionshinweise.
    public var notes: [String]
    /// Mit Homebrew installiert: Das Update läuft über `brew upgrade`, sonst öffnet sich die Seite.
    public var viaHomebrew: Bool

    public init(version: String, pageURL: String, notes: [String], viaHomebrew: Bool) {
        self.version = version
        self.pageURL = pageURL
        self.notes = notes
        self.viaHomebrew = viaHomebrew
    }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(UpdateOffer)
    case releaseAvailable(ReleaseOffer)
    /// Ein Update gibt es, aber es würde etwas überschreiben; der Text sagt, was zu tun ist.
    case blocked(String)
    case installing(String)
    case failed(String)
    /// Diese App wurde nicht aus einem Git-Ordner gebaut.
    case unavailable(String)
}

public struct UpdateError: Error, Equatable, Sendable {
    public var message: String
}

/// Prüft per Git, ob es im Repository einen neueren Stand gibt, und holt und baut ihn.
/// Es wird nur vorgespult (`--ff-only`); lokale Änderungen und eigene Commits werden nie überschrieben.
public struct UpdateChecker: Sendable {
    private let sourceDirectory: String
    private let runner: any CommandRunning
    private let logPath: String

    public init(sourceDirectory: String, runner: any CommandRunning, logPath: String) {
        self.sourceDirectory = sourceDirectory
        self.runner = runner
        self.logPath = logPath
    }

    private func git(_ arguments: String) async -> CommandResult {
        await runner.run("git " + arguments, in: sourceDirectory)
    }

    public func check() async -> UpdateState {
        guard await git("rev-parse --is-inside-work-tree").trimmed == "true" else {
            return .unavailable(L("„{0}“ ist kein Git-Ordner mehr.", sourceDirectory))
        }
        let fetch = await git("fetch --prune --quiet origin")
        guard fetch.succeeded else {
            return .failed(L("GitHub ist nicht erreichbar: {0}", fetch.trimmed))
        }
        let branch = await git("rev-parse --abbrev-ref HEAD").trimmed

        // Ist der Branch auf GitHub verschwunden (gemergt und gelöscht), geht es auf dem Standard-Branch weiter.
        var upstream = ""
        var switchTo: String?
        let tracked = await git("rev-parse --abbrev-ref --symbolic-full-name '@{u}'")
        if tracked.succeeded, !tracked.trimmed.isEmpty {
            upstream = tracked.trimmed
        } else {
            let defaultBranch = await git("rev-parse --abbrev-ref origin/HEAD")
            upstream = defaultBranch.succeeded && !defaultBranch.trimmed.isEmpty ? defaultBranch.trimmed : "origin/main"
            switchTo = String(upstream.dropFirst("origin/".count))
            if switchTo == branch { switchTo = nil }
        }

        let behind = Int(await git("rev-list --count HEAD..\(upstream)").trimmed) ?? 0
        guard behind > 0 || switchTo != nil else { return .upToDate }
        let subjects = await git("log --format=%s -n 20 HEAD..\(upstream)").output
            .split(separator: "\n").map(String.init)

        if !(await git("status --porcelain --untracked-files=no").trimmed.isEmpty) {
            return .blocked(L("Lokale Änderungen in „{0}“. Erst committen oder verwerfen, dann aktualisieren.", sourceDirectory))
        }
        if switchTo == nil, (Int(await git("rev-list --count \(upstream)..HEAD").trimmed) ?? 0) > 0 {
            return .blocked(L("Dein Stand hat eigene Commits, die nicht auf GitHub sind. Erst pushen, dann aktualisieren."))
        }
        return .available(UpdateOffer(count: behind, subjects: subjects, branch: branch, upstream: upstream, switchTo: switchTo))
    }

    /// Holt den neuen Stand und baut die App; gibt den Pfad der frisch gebauten App zurück.
    public func install(_ offer: UpdateOffer, progress: @Sendable (String) -> Void = { _ in }) async -> Result<String, UpdateError> {
        if let target = offer.switchTo {
            progress(L("Wechsle auf {0} …", target))
            let switched = await git("switch --quiet \(ShellQuote.quote(target))")
            guard switched.succeeded else { return .failure(UpdateError(message: L("Wechsel auf {0} ging nicht: {1}", target, switched.trimmed))) }
        }
        progress(L("Hole den neuen Stand …"))
        let merged = await git("merge --ff-only --quiet \(offer.upstream)")
        guard merged.succeeded else { return .failure(UpdateError(message: L("Vorspulen ging nicht: {0}", merged.trimmed))) }

        progress(L("Baue lumo (das dauert ein bis zwei Minuten) …"))
        let log = ShellQuote.quote(logPath)
        let built = await runner.run("scripts/build-app.sh > \(log) 2>&1", in: sourceDirectory)
        guard built.succeeded else {
            let tail = await runner.run("tail -n 15 \(log)", in: sourceDirectory).trimmed
            return .failure(UpdateError(message: L("Bauen fehlgeschlagen:\n{0}", tail)))
        }
        return .success(URL(filePath: sourceDirectory).appending(path: "build/lumo.app").path)
    }
}
