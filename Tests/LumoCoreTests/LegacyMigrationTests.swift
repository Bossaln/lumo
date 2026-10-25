import Foundation
import Testing
@testable import LumoCore

private let newBin = "/Users/x/Library/Application Support/lumo/bin/lumo-hook"
private let oldBin = "/Users/x/Library/Application Support/notchai/bin/notchai-hook"

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "lumo-migration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func commands(_ home: URL, _ file: String, _ event: String) throws -> [String] {
    let root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: home.appending(path: file)))
    return (root["hooks"]?[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }.compactMap { $0["command"]?.stringValue }
}

@Test func migrationCopiesFilesOnlyWhereLumoHasNone() throws {
    let home = try makeHome()
    let old = LegacyMigration.legacyAppSupport(home: home)
    let new = LumoPaths.appSupport(home: home)
    try write(#"{"glowEnabled":false}"#, to: old.appending(path: "settings.json"))
    try write(#"{"notes":[]}"#, to: old.appending(path: "notes.json"))
    try write(#"{"items":[]}"#, to: new.appending(path: "shelf.json"))
    try write(#"{"items":["alt"]}"#, to: old.appending(path: "shelf.json"))

    let copied = try LegacyMigration.migrateFiles(home: home)
    #expect(copied == ["settings.json", "notes.json"])
    #expect(try String(contentsOf: new.appending(path: "settings.json"), encoding: .utf8) == #"{"glowEnabled":false}"#)
    // Vorhandene lumo-Dateien bleiben, der alte Ordner auch.
    #expect(try String(contentsOf: new.appending(path: "shelf.json"), encoding: .utf8) == #"{"items":[]}"#)
    #expect(FileManager.default.fileExists(atPath: old.appending(path: "settings.json").path))
    // Ein zweiter Lauf tut nichts mehr.
    #expect(try LegacyMigration.migrateFiles(home: home).isEmpty)
}

@Test func migrationWithoutLegacyFolderDoesNothing() throws {
    let home = try makeHome()
    #expect(try LegacyMigration.migrateFiles(home: home).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: LumoPaths.appSupport(home: home).path))
}

@Test func legacyHooksAreReplacedOnlyWhereTheyExist() throws {
    let home = try makeHome()
    try write(#"{"model":"opus","hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/other"},{"type":"command","command":"\"\#(oldBin)\" claude event","async":true,"timeout":5}]}],"PermissionRequest":[{"matcher":"","hooks":[{"type":"command","command":"\"\#(oldBin)\" claude decide","timeout":130}]}]}}"#,
              to: home.appending(path: ".claude/settings.json"))
    try write(#"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/usr/local/bin/other"}]}]}}"#,
              to: home.appending(path: ".codex/hooks.json"))
    let installer = HookInstaller(home: home, hookBinaryPath: newBin)
    #expect(try installer.legacyStatus() == HookInstallStatus(claudeInstalled: true, codexInstalled: false))

    let migrated = try installer.migrateLegacy()
    #expect(migrated == HookInstallStatus(claudeInstalled: true, codexInstalled: false))
    let stop = try commands(home, ".claude/settings.json", "Stop")
    #expect(stop.contains("/usr/local/bin/other"))
    #expect(stop.filter { $0.contains("notchai") }.isEmpty)
    #expect(stop.filter { $0 == "\"\(newBin)\" claude event" }.count == 1)
    #expect(try commands(home, ".claude/settings.json", "PermissionRequest") == ["\"\(newBin)\" claude decide"])
    // Codex hatte keine notchai-Hooks und bekommt auch keine lumo-Hooks.
    #expect(try commands(home, ".codex/hooks.json", "Stop") == ["/usr/local/bin/other"])
    #expect(try installer.legacyStatus() == HookInstallStatus(claudeInstalled: false, codexInstalled: false))
    #expect(try installer.status() == HookInstallStatus(claudeInstalled: true, codexInstalled: false))
}

@Test func uninstallAlsoRemovesLegacyEntries() throws {
    let home = try makeHome()
    try write(#"{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"\"\#(oldBin)\" claude event"}]}]}}"#,
              to: home.appending(path: ".claude/settings.json"))
    try HookInstaller(home: home, hookBinaryPath: newBin).uninstallAll()
    let root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: home.appending(path: ".claude/settings.json")))
    #expect(root["hooks"] == nil)
}
