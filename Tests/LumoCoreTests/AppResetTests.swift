import Foundation
import Testing
@testable import LumoCore

private let bundleID = "com.bossaln.lumo"

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "lumo-reset-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func touch(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: url)
}

@Test func resetCoversEverythingLumoLeavesOnTheMac() throws {
    let home = URL(filePath: "/Users/x")
    let paths = Set(AppReset.dataLocations(home: home, bundleID: bundleID).map(\.path))
    #expect(paths == [
        "/Users/x/Library/Application Support/lumo",
        "/Users/x/Library/Logs/lumo",
        "/Users/x/Library/Caches/com.bossaln.lumo",
        "/Users/x/Library/HTTPStorages/com.bossaln.lumo",
        "/Users/x/Library/HTTPStorages/com.bossaln.lumo.binarycookies",
        "/Users/x/Library/Saved Application State/com.bossaln.lumo.savedState",
        "/Users/x/Library/Preferences/com.bossaln.lumo.plist",
    ])
}

@Test func resetRemovesHooksAndAllData() throws {
    let home = try makeHome()
    let bin = LumoPaths.hookBinary(home: home).path
    try touch(home.appending(path: ".claude/settings.json"))
    try Data(#"{"model":"opus"}"#.utf8).write(to: home.appending(path: ".claude/settings.json"))
    let installer = HookInstaller(home: home, hookBinaryPath: bin)
    try installer.installClaude()
    try touch(LumoPaths.appSupport(home: home).appending(path: "settings.json"))
    try touch(home.appending(path: "Library/Logs/lumo/update.log"))
    try touch(home.appending(path: "Library/Caches/\(bundleID)/Cache.db"))

    var removed: [String] = []
    try AppReset.perform(home: home, bundleID: bundleID, installer: installer) { url in
        removed.append(url.lastPathComponent)
        try FileManager.default.removeItem(at: url)
    }

    // Die Hooks sind aus Claude Code entfernt, fremde Einstellungen bleiben.
    #expect(try !installer.status().claudeInstalled)
    let settings = try String(contentsOf: home.appending(path: ".claude/settings.json"), encoding: .utf8)
    #expect(settings.contains("opus"))
    // Alles von lumo ist weg; was es nicht gab, wird übersprungen.
    #expect(!FileManager.default.fileExists(atPath: LumoPaths.appSupport(home: home).path))
    #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Library/Logs/lumo").path))
    #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/\(bundleID)").path))
    #expect(removed.sorted() == ["com.bossaln.lumo", "lumo", "lumo"])
}
