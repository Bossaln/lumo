import Foundation
import Testing
@testable import NotchaiCore

private let bin = "/Users/x/Library/Application Support/notchai/bin/notchai-hook"

/// Wegwerf-Home mit optionalen Startdateien.
private func makeTempHome(claudeSettings: String? = nil, codexHooks: String? = nil, codexConfig: String? = nil) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "notchai-home-\(UUID().uuidString)")
    let fm = FileManager.default
    if let claudeSettings {
        try fm.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        try Data(claudeSettings.utf8).write(to: home.appending(path: ".claude/settings.json"))
    }
    if codexHooks != nil || codexConfig != nil {
        try fm.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
    }
    if let codexHooks { try Data(codexHooks.utf8).write(to: home.appending(path: ".codex/hooks.json")) }
    if let codexConfig { try Data(codexConfig.utf8).write(to: home.appending(path: ".codex/config.toml")) }
    try fm.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func readJSON(_ home: URL, _ path: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: home.appending(path: path)))
}

/// Alle Hook-Definitionen eines Ereignisses (über alle Gruppen).
private func definitions(_ root: JSONValue, _ event: String, matcher: String? = nil) -> [JSONValue] {
    (root["hooks"]?[event]?.arrayValue ?? [])
        .filter { matcher == nil || $0["matcher"]?.stringValue == matcher }
        .flatMap { $0["hooks"]?.arrayValue ?? [] }
}

private func commands(_ root: JSONValue, _ event: String, matcher: String? = nil) -> [String] {
    definitions(root, event, matcher: matcher).compactMap { $0["command"]?.stringValue }
}

private func backups(_ home: URL) throws -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: NotchaiPaths.backupsDir(home: home), includingPropertiesForKeys: nil)) ?? []
}

@Test func installIsIdempotentAndKeepsForeignHooks() throws {
    let home = try makeTempHome(claudeSettings: #"{"model":"opus","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/other"}]}]}}"#)
    let inst = HookInstaller(home: home, hookBinaryPath: bin)
    try inst.installClaude(); try inst.installClaude()
    let s = try readJSON(home, ".claude/settings.json")
    #expect(s["model"]?.stringValue == "opus")
    #expect(commands(s, "Stop").filter { $0.contains("/usr/local/bin/other") }.count == 1)
    #expect(commands(s, "Stop").filter { $0.contains("notchai-hook") }.count == 1)
    #expect(commands(s, "PermissionRequest") == [#""/Users/x/Library/Application Support/notchai/bin/notchai-hook" claude decide"#])
}

@Test func askUserQuestionHasOwnDecideMatcher() throws {
    let home = try makeTempHome()
    try HookInstaller(home: home, hookBinaryPath: bin).installClaude()
    let s = try readJSON(home, ".claude/settings.json")
    let ask = definitions(s, "PreToolUse", matcher: "AskUserQuestion")
    #expect(ask.count == 1)
    #expect(ask.first?["command"]?.stringValue == #""\#(bin)" claude decide"#)
    #expect(ask.first?["timeout"]?.numberValue == 130)
    #expect(ask.first?["async"] == nil)
    // Daneben gibt es das normale Ereignis für alle Werkzeuge.
    #expect(commands(s, "PreToolUse", matcher: "") == [#""\#(bin)" claude event"#])
}

@Test func eventHooksAreAsyncWithShortTimeout() throws {
    let home = try makeTempHome()
    try HookInstaller(home: home, hookBinaryPath: bin).installClaude()
    let s = try readJSON(home, ".claude/settings.json")
    let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                  "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop"]
    for event in events {
        let defs = definitions(s, event).filter { $0["command"]?.stringValue?.hasSuffix(" claude event") == true }
        #expect(defs.count == 1, "\(event)")
        #expect(defs.first?["async"]?.boolValue == true, "\(event)")
        #expect(defs.first?["timeout"]?.numberValue == 5, "\(event)")
        #expect(defs.first?["type"]?.stringValue == "command", "\(event)")
    }
    #expect(definitions(s, "PermissionRequest").first?["timeout"]?.numberValue == 130)
}

@Test func backupIsWrittenBeforeChange() throws {
    let original = #"{"model":"opus"}"#
    let home = try makeTempHome(claudeSettings: original)
    let inst = HookInstaller(home: home, hookBinaryPath: bin, now: { Date(timeIntervalSince1970: 1_792_683_988) })
    try inst.installClaude()
    let files = try backups(home)
    #expect(files.count == 1)
    #expect(files.first?.lastPathComponent.hasPrefix("claude-settings-") == true)
    #expect(try String(contentsOf: try #require(files.first), encoding: .utf8) == original)
    // Ein zweites Einrichten ändert nichts und sichert deshalb auch nichts.
    try inst.installClaude()
    #expect(try backups(home).count == 1)
}

@Test func backupsInTheSameSecondDoNotOverwriteEachOther() throws {
    let home = try makeTempHome(claudeSettings: #"{"model":"opus"}"#)
    let inst = HookInstaller(home: home, hookBinaryPath: bin, now: { Date(timeIntervalSince1970: 1_792_683_988) })
    try inst.installClaude()
    try inst.uninstallAll()
    let contents = try backups(home).map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(contents.count == 2)
    #expect(contents.contains(#"{"model":"opus"}"#))
}

@Test func uninstallRemovesOnlyNotchai() throws {
    let before = #"{"statusLine":{"type":"command","command":"~/bin/status"},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/other"}]}]}}"#
    let home = try makeTempHome(claudeSettings: before)
    let inst = HookInstaller(home: home, hookBinaryPath: bin)
    try inst.installClaude()
    #expect(try inst.status().claudeInstalled)
    try inst.uninstallAll()
    #expect(try !inst.status().claudeInstalled)
    let after = try readJSON(home, ".claude/settings.json")
    #expect(after == (try JSONDecoder().decode(JSONValue.self, from: Data(before.utf8))))
}

@Test func codexWritesHooksJsonButNeverConfigToml() throws {
    let config = "notify = [\"/Applications/Codex Computer Use.app/notify\"]\nmodel = \"gpt-6.1\"\n"
    let home = try makeTempHome(codexConfig: config)
    let inst = HookInstaller(home: home, hookBinaryPath: bin)
    try inst.installCodex()
    #expect(try String(contentsOf: home.appending(path: ".codex/config.toml"), encoding: .utf8) == config)
    let h = try readJSON(home, ".codex/hooks.json")
    #expect(commands(h, "Stop") == [#""\#(bin)" codex event"#])
    #expect(commands(h, "PermissionRequest") == [#""\#(bin)" codex decide"#])
    #expect(try inst.status().codexInstalled)
    #expect(try !inst.status().claudeInstalled)
}

@Test func codexSessionEndRunsSynchronouslyWithinThreeSeconds() throws {
    // Codex führt SessionEnd ohnehin synchron aus und kürzt auf 3 s; so gibt es keine Warnungen.
    let home = try makeTempHome()
    try HookInstaller(home: home, hookBinaryPath: bin).installCodex()
    let end = definitions(try readJSON(home, ".codex/hooks.json"), "SessionEnd")
    #expect(end.count == 1)
    #expect(end.first?["async"] == nil)
    #expect(end.first?["timeout"]?.numberValue == 3)
}

@Test func missingSettingsFileIsCreated() throws {
    let home = try makeTempHome()
    let inst = HookInstaller(home: home, hookBinaryPath: bin)
    try inst.installClaude()
    #expect(FileManager.default.fileExists(atPath: home.appending(path: ".claude/settings.json").path))
    #expect(try inst.status().claudeInstalled)
    #expect(try backups(home).isEmpty)
}

@Test func brokenSettingsAreNeverOverwritten() throws {
    let broken = #"{"model":"opus", // Kommentar"#
    let home = try makeTempHome(claudeSettings: broken)
    let inst = HookInstaller(home: home, hookBinaryPath: bin)
    #expect(throws: HookInstallerError.self) { try inst.installClaude() }
    #expect(try String(contentsOf: home.appending(path: ".claude/settings.json"), encoding: .utf8) == broken)
}

@Test func changedBinaryPathReplacesOldEntries() throws {
    let home = try makeTempHome()
    try HookInstaller(home: home, hookBinaryPath: "/alt/notchai/bin/notchai-hook").installClaude()
    try HookInstaller(home: home, hookBinaryPath: bin).installClaude()
    let s = try readJSON(home, ".claude/settings.json")
    #expect(commands(s, "Stop") == [#""\#(bin)" claude event"#])
}

@Test func copyHookBinaryInstallsExecutableOnlyWhenChanged() throws {
    let home = try makeTempHome()
    let source = home.appending(path: "notchai-hook-neu")
    try Data("programm".utf8).write(to: source)
    let inst = HookInstaller(home: home, hookBinaryPath: NotchaiPaths.hookBinary(home: home).path)
    #expect(try inst.copyHookBinary(from: source) == true)
    let target = NotchaiPaths.hookBinary(home: home)
    #expect(FileManager.default.isExecutableFile(atPath: target.path))
    #expect(try Data(contentsOf: target) == Data("programm".utf8))
    #expect(try inst.copyHookBinary(from: source) == false)
}
