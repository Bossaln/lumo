import Foundation
import Testing
@testable import LumoCore

/// Spielt Git nach: Jedes Kommando bekommt eine feste Antwort; unbekannte scheitern. Merkt sich die Reihenfolge.
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    var answers: [String: CommandResult]
    private(set) var log: [String] = []
    private let lock = NSLock()

    init(_ answers: [String: CommandResult]) {
        self.answers = answers
    }

    func run(_ command: String, in directory: String) async -> CommandResult {
        lock.withLock {
            log.append(command)
            return answers[command] ?? CommandResult(status: 1, output: "unbekannt: \(command)")
        }
    }
}

private func ok(_ output: String = "") -> CommandResult { CommandResult(status: 0, output: output) }
private func fail(_ output: String = "") -> CommandResult { CommandResult(status: 1, output: output) }

/// Ein sauberer Stand auf `feature`, der `origin/feature` verfolgt.
private func cleanRepo(behind: Int, subjects: [String] = []) -> [String: CommandResult] {
    [
        "git rev-parse --is-inside-work-tree": ok("true\n"),
        "git fetch --prune --quiet origin": ok(),
        "git rev-parse --abbrev-ref HEAD": ok("feature\n"),
        "git rev-parse --abbrev-ref --symbolic-full-name '@{u}'": ok("origin/feature\n"),
        "git rev-list --count HEAD..origin/feature": ok("\(behind)\n"),
        "git rev-list --count origin/feature..HEAD": ok("0\n"),
        "git log --format=%s -n 20 HEAD..origin/feature": ok(subjects.joined(separator: "\n") + "\n"),
        "git status --porcelain --untracked-files=no": ok(""),
    ]
}

@Test func upToDateWhenNothingNew() async {
    let checker = UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(cleanRepo(behind: 0)), logPath: "/tmp/u.log")
    #expect(await checker.check() == .upToDate)
}

@Test func newCommitsAreOffered() async {
    let checker = UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(cleanRepo(behind: 2, subjects: ["Neu A", "Neu B"])),
                                logPath: "/tmp/u.log")
    #expect(await checker.check() == .available(UpdateOffer(count: 2, subjects: ["Neu A", "Neu B"], branch: "feature",
                                                            upstream: "origin/feature", switchTo: nil)))
}

@Test func localChangesBlockTheUpdate() async {
    var answers = cleanRepo(behind: 1)
    answers["git status --porcelain --untracked-files=no"] = ok(" M Sources/x.swift\n")
    let state = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(answers), logPath: "/tmp/u.log").check()
    guard case .blocked(let reason) = state else { Issue.record("erwartet blockiert, war \(state)"); return }
    #expect(reason.contains("Lokale Änderungen"))
}

@Test func ownUnpushedCommitsBlockTheUpdate() async {
    var answers = cleanRepo(behind: 1)
    answers["git rev-list --count origin/feature..HEAD"] = ok("3\n")
    let state = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(answers), logPath: "/tmp/u.log").check()
    guard case .blocked = state else { Issue.record("erwartet blockiert, war \(state)"); return }
}

@Test func deletedBranchSwitchesToTheDefaultBranch() async {
    // Nach dem Mergen löscht GitHub den Branch; dann geht es auf main weiter.
    var answers = cleanRepo(behind: 0)
    answers["git rev-parse --abbrev-ref --symbolic-full-name '@{u}'"] = fail("fatal: no upstream configured")
    answers["git rev-parse --abbrev-ref origin/HEAD"] = ok("origin/main\n")
    answers["git rev-list --count HEAD..origin/main"] = ok("4\n")
    answers["git log --format=%s -n 20 HEAD..origin/main"] = ok("Merge pull request #3\n")
    let state = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(answers), logPath: "/tmp/u.log").check()
    #expect(state == .available(UpdateOffer(count: 4, subjects: ["Merge pull request #3"], branch: "feature",
                                            upstream: "origin/main", switchTo: "main")))
}

@Test func offlineIsReportedNotHidden() async {
    var answers = cleanRepo(behind: 0)
    answers["git fetch --prune --quiet origin"] = fail("ssh: Could not resolve hostname github.com")
    let state = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(answers), logPath: "/tmp/u.log").check()
    guard case .failed(let message) = state else { Issue.record("erwartet Fehler, war \(state)"); return }
    #expect(message.contains("Could not resolve hostname"))
}

@Test func notARepositoryIsUnavailable() async {
    let state = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner([:]), logPath: "/tmp/u.log").check()
    guard case .unavailable = state else { Issue.record("erwartet nicht verfügbar, war \(state)"); return }
}

@Test func installPullsThenBuilds() async throws {
    var answers = cleanRepo(behind: 1)
    answers["git merge --ff-only --quiet origin/feature"] = ok()
    answers["scripts/build-app.sh > '/tmp/u log.txt' 2>&1"] = ok()
    let runner = FakeRunner(answers)
    let checker = UpdateChecker(sourceDirectory: "/src", runner: runner, logPath: "/tmp/u log.txt")
    let offer = UpdateOffer(count: 1, subjects: [], branch: "feature", upstream: "origin/feature", switchTo: nil)
    let app = try await checker.install(offer).get()
    #expect(app == "/src/build/lumo.app")
    #expect(runner.log.suffix(2) == ["git merge --ff-only --quiet origin/feature", "scripts/build-app.sh > '/tmp/u log.txt' 2>&1"])
}

@Test func installSwitchesBranchFirstWhenAsked() async throws {
    var answers: [String: CommandResult] = [:]
    answers["git switch --quiet main"] = ok()
    answers["git merge --ff-only --quiet origin/main"] = ok()
    answers["scripts/build-app.sh > /tmp/u.log 2>&1"] = ok()
    let runner = FakeRunner(answers)
    let offer = UpdateOffer(count: 4, subjects: [], branch: "feature", upstream: "origin/main", switchTo: "main")
    _ = try await UpdateChecker(sourceDirectory: "/src", runner: runner, logPath: "/tmp/u.log").install(offer).get()
    #expect(runner.log == ["git switch --quiet main", "git merge --ff-only --quiet origin/main", "scripts/build-app.sh > /tmp/u.log 2>&1"])
}

@Test func failedBuildShowsTheEndOfTheLog() async {
    var answers: [String: CommandResult] = [:]
    answers["git merge --ff-only --quiet origin/feature"] = ok()
    answers["scripts/build-app.sh > /tmp/u.log 2>&1"] = fail()
    answers["tail -n 15 /tmp/u.log"] = ok("error: cannot find 'x' in scope\n")
    let offer = UpdateOffer(count: 1, subjects: [], branch: "feature", upstream: "origin/feature", switchTo: nil)
    let result = await UpdateChecker(sourceDirectory: "/src", runner: FakeRunner(answers), logPath: "/tmp/u.log").install(offer)
    guard case .failure(let error) = result else { Issue.record("Bauen sollte scheitern"); return }
    #expect(error.message.contains("cannot find 'x'"))
}

@Test func shellQuoteKeepsSpacesAndQuotes() {
    #expect(ShellQuote.quote("/Users/x/Developer/lumo") == "/Users/x/Developer/lumo")
    #expect(ShellQuote.quote("/Users/x/Mein Projekt") == "'/Users/x/Mein Projekt'")
    #expect(ShellQuote.quote("it's") == #"'it'\''s'"#)
    #expect(ShellQuote.quote("") == "''")
}

@Test func buildInfoReadsTheBundle() {
    let info = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "57",
                                          "LumoGitCommit": "abc1234", "LumoGitBranch": "main",
                                          "LumoSourceDirectory": "/Users/x/Developer/lumo"])
    #expect(info.displayVersion == "0.2.0 (abc1234, main)")
    #expect(info.sourceDirectory == "/Users/x/Developer/lumo")
    let bare = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.2.0"])
    #expect(bare.displayVersion == "0.2.0")
    #expect(bare.sourceDirectory == nil)
}
