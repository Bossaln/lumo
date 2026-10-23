import Foundation
import Testing
@testable import NotchaiCore

/// Führt Kommandos wirklich mit `/bin/sh` aus, wie es die App mit der Login-Shell tut.
private struct ShellRunner: CommandRunning {
    func run(_ command: String, in directory: String) async -> CommandResult {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "cd \(ShellQuote.quote(directory)) && \(command)"]
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Eigene Git-Einstellungen des Besitzers (Signatur, Hooks …) bleiben außen vor.
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return CommandResult(status: -1, output: "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

/// Wegwerf-„GitHub“ (bare) mit einem Klon, der `feature` verfolgt; `main` ist Standard-Branch.
private struct GitFixture {
    let root: URL
    let origin: String
    let clone: String
    let runner = ShellRunner()

    init() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "notchai-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        origin = root.appending(path: "origin.git").path
        clone = root.appending(path: "klon").path
        let author = root.appending(path: "autor").path
        try await sh("git init -q --bare -b main \(ShellQuote.quote(origin))", in: root.path)
        try await sh("git clone -q \(ShellQuote.quote(origin)) autor", in: root.path)
        try await sh(Self.identity + " && mkdir -p scripts && printf '#!/bin/sh\\necho gebaut > gebaut.txt\\n' > scripts/build-app.sh && chmod +x scripts/build-app.sh && git add -A && git commit -q -m Start && git push -q origin HEAD:main", in: author)
        try await sh("git switch -q -c feature && git commit -q --allow-empty -m 'Feature 1' && git push -q -u origin feature", in: author)
        try await sh("git clone -q -b feature \(ShellQuote.quote(origin)) klon && cd klon && " + Self.identity, in: root.path)
    }

    static let identity = "git config user.email t@example.com && git config user.name Test"

    @discardableResult
    func sh(_ command: String, in directory: String) async throws -> String {
        let result = await runner.run(command, in: directory)
        guard result.status == 0 else { throw GitFixtureError(command: command, output: result.output) }
        return result.output
    }

    /// Ein weiterer Commit auf `branch` im Ursprung (wie ein Push von einem anderen Rechner).
    func pushCommit(_ message: String, to branch: String) async throws {
        try await sh("git fetch -q origin && git switch -q \(branch) && git merge -q --ff-only origin/\(branch) && git commit -q --allow-empty -m \(ShellQuote.quote(message)) && git push -q origin \(branch)",
                     in: root.appending(path: "autor").path)
    }

    var checker: UpdateChecker {
        UpdateChecker(sourceDirectory: clone, runner: runner, logPath: root.appending(path: "update.log").path)
    }
}

private struct GitFixtureError: Error, CustomStringConvertible {
    let command: String
    let output: String
    var description: String { "\(command)\n\(output)" }
}

private let gitAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/git")

@Test(.enabled(if: gitAvailable)) func realGitUpToDateThenAvailableThenInstalled() async throws {
    let git = try await GitFixture()
    #expect(await git.checker.check() == .upToDate)

    try await git.pushCommit("Neue Notch-Farbe", to: "feature")
    let state = await git.checker.check()
    guard case .available(let offer) = state else { Issue.record("erwartet Update, war \(state)"); return }
    #expect(offer.count == 1)
    #expect(offer.subjects == ["Neue Notch-Farbe"])
    #expect(offer.branch == "feature")
    #expect(offer.upstream == "origin/feature")
    #expect(offer.switchTo == nil)

    let built = try await git.checker.install(offer).get()
    #expect(built == git.clone + "/build/notchai.app")
    #expect(FileManager.default.fileExists(atPath: git.clone + "/gebaut.txt"))
    #expect(await git.checker.check() == .upToDate)
}

@Test(.enabled(if: gitAvailable)) func realGitLocalChangesBlock() async throws {
    let git = try await GitFixture()
    try await git.pushCommit("Etwas Neues", to: "feature")
    try await git.sh("echo geändert >> scripts/build-app.sh", in: git.clone)
    guard case .blocked = await git.checker.check() else { Issue.record("lokale Änderung muss blockieren"); return }
}

@Test(.enabled(if: gitAvailable)) func realGitDeletedBranchMovesToMain() async throws {
    // So sieht es nach dem Mergen aus: Der Feature-Branch ist auf GitHub gelöscht, main hat den Merge.
    let git = try await GitFixture()
    let author = git.root.appending(path: "autor").path
    try await git.sh("git switch -q main && git merge -q --no-ff feature -m 'Merge pull request #3' && git push -q origin main && git push -q origin --delete feature", in: author)
    let state = await git.checker.check()
    guard case .available(let offer) = state else { Issue.record("erwartet Wechsel auf main, war \(state)"); return }
    #expect(offer.switchTo == "main")
    #expect(offer.upstream == "origin/main")
    _ = try await git.checker.install(offer).get()
    #expect(try await git.sh("git rev-parse --abbrev-ref HEAD", in: git.clone).trimmingCharacters(in: .whitespacesAndNewlines) == "main")
    #expect(await git.checker.check() == .upToDate)
}
