import Foundation
import Testing
@testable import LumoCore

@MainActor @Test func savesAndReloads() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID()).json")
    let a = SettingsStore(fileURL: url)
    a.settings.signalStyle = .vertical
    let b = SettingsStore(fileURL: url)
    #expect(b.settings.signalStyle == .vertical)
}

@MainActor @Test func corruptFileGivesDefaults() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID()).json")
    try Data("{kaputt".utf8).write(to: url)
    #expect(SettingsStore(fileURL: url).settings == AppSettings.default)
}

@MainActor @Test func createsMissingDirectory() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID())")
    let store = SettingsStore(fileURL: dir.appending(path: "settings.json"))
    store.settings.soundsEnabled = false
    #expect(FileManager.default.fileExists(atPath: dir.appending(path: "settings.json").path))
}

@MainActor @Test func frozenStoreNoLongerWrites() throws {
    // Beim Zurücksetzen darf nichts die gerade gelöschte Datei wieder anlegen.
    let url = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID()).json")
    let store = SettingsStore(fileURL: url)
    store.freeze()
    store.settings.setupCompleted = true
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
