import Foundation
import Testing
@testable import NotchaiCore

private let bundleID = "com.bossaln.notchai"

private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "notchai-reset-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func touch(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: url)
}

@Test func resetCoversEverythingNotchaiLeavesOnTheMac() throws {
    let home = URL(filePath: "/Users/x")
    let paths = Set(AppReset.dataLocations(home: home, bundleID: bundleID).map(\.path))
    #expect(paths == [
        "/Users/x/Library/Application Support/notchai",
        "/Users/x/Library/Logs/notchai",
        "/Users/x/Library/Caches/com.bossaln.notchai",
        "/Users/x/Library/HTTPStorages/com.bossaln.notchai",
        "/Users/x/Library/HTTPStorages/com.bossaln.notchai.binarycookies",
        "/Users/x/Library/Saved Application State/com.bossaln.notchai.savedState",
        "/Users/x/Library/Preferences/com.bossaln.notchai.plist",
    ])
}

@Test func resetRemovesHooksAndAllData() throws {
    let home = try makeHome()
    let bin = NotchaiPaths.hookBinary(home: home).path
    try touch(home.appending(path: ".claude/settings.json"))
    try Data(#"{"model":"opus"}"#.utf8).write(to: home.appending(path: ".claude/settings.json"))
    let installer = HookInstaller(home: home, hookBinaryPath: bin)
    try installer.installClaude()
    try touch(NotchaiPaths.appSupport(home: home).appending(path: "settings.json"))
    try touch(home.appending(path: "Library/Logs/notchai/update.log"))
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
    // Alles von notchai ist weg; was es nicht gab, wird übersprungen.
    #expect(!FileManager.default.fileExists(atPath: NotchaiPaths.appSupport(home: home).path))
    #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Library/Logs/notchai").path))
    #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Library/Caches/\(bundleID)").path))
    #expect(removed.sorted() == ["com.bossaln.notchai", "notchai", "notchai"])
}
