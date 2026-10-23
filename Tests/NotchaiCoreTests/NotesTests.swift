import Foundation
import Testing
@testable import NotchaiCore

private let t0 = Date(timeIntervalSince1970: 1_792_800_000)

// MARK: - Notizbuch

@Test func notesAreTrimmedAndNewestComesFirst() {
    var book = NoteBook()
    book.add("  Milch kaufen \n", now: t0)
    book.add("PR prüfen", now: t0.addingTimeInterval(60))
    #expect(book.notes.map(\.text) == ["PR prüfen", "Milch kaufen"])
    #expect(book.notes.last?.createdAt == t0)
}

@Test func emptyNotesAreIgnored() {
    var book = NoteBook()
    #expect(book.add("   \n ", now: t0) == nil)
    #expect(book.notes.isEmpty)
}

@Test func notesCanBeRemovedOneByOneOrAllAtOnce() {
    var book = NoteBook()
    let first = book.add("eins", now: t0)!
    book.add("zwei", now: t0)
    book.remove(first.id)
    #expect(book.notes.map(\.text) == ["zwei"])
    book.removeAll()
    #expect(book.notes.isEmpty)
}

@Test func oldestNotesFallOutAtTheLimit() {
    var book = NoteBook()
    for index in 0..<(NoteBook.limit + 3) { book.add("Notiz \(index)", now: t0.addingTimeInterval(Double(index))) }
    #expect(book.notes.count == NoteBook.limit)
    #expect(book.notes.first?.text == "Notiz \(NoteBook.limit + 2)")
    #expect(!book.notes.contains { $0.text == "Notiz 0" })
}

@MainActor @Test func notesSurviveARestart() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "notchai-notes-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "notes.json")
    let store = NoteStore(fileURL: file)
    store.add("Idee für morgen")
    let reloaded = NoteStore(fileURL: file)
    #expect(reloaded.book.notes.map(\.text) == ["Idee für morgen"])
}

@MainActor @Test func unreadableNotesStartEmpty() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "notchai-notes-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "notes.json")
    try Data("kaputt".utf8).write(to: file)
    #expect(NoteStore(fileURL: file).book.notes.isEmpty)
}

// MARK: - Zweimal ⌃

// Rohwerte von `NSEvent.modifierFlags`: ⌃ (geräteunabhängig) und die Bits der linken bzw. rechten ⌃-Taste.
private let leftControlDown: UInt64 = (1 << 18) | 0x01
private let rightControlDown: UInt64 = (1 << 18) | 0x2000

private func tap(_ tracker: inout ModifierTapTracker, keyCode: UInt16 = 59, down: UInt64 = leftControlDown,
                 at seconds: Double, hold: Double = 0.1) -> Bool {
    _ = tracker.flagsChanged(keyCode: keyCode, flags: down, at: t0.addingTimeInterval(seconds))
    return tracker.flagsChanged(keyCode: keyCode, flags: 0, at: t0.addingTimeInterval(seconds + hold))
}

@Test func controlDoubleTapOpensANote() {
    var left = ModifierTapTracker(key: .control)
    let leftTaps = [tap(&left, at: 0), tap(&left, at: 0.25)]
    #expect(leftTaps == [false, true])
    var right = ModifierTapTracker(key: .control)
    let rightTaps = [tap(&right, keyCode: 62, down: rightControlDown, at: 0),
                     tap(&right, keyCode: 62, down: rightControlDown, at: 0.25)]
    #expect(rightTaps == [false, true])
}

@Test func controlShortcutsDoNotCount() {
    var tracker = ModifierTapTracker(key: .control)
    _ = tap(&tracker, at: 0)
    // ⌃C: Dazwischen kommt eine andere Taste.
    _ = tracker.flagsChanged(keyCode: 59, flags: leftControlDown, at: t0.addingTimeInterval(0.2))
    tracker.keyDown()
    let released = tracker.flagsChanged(keyCode: 59, flags: 0, at: t0.addingTimeInterval(0.3))
    #expect(!released)
}

@Test func commandDoesNotOpenANote() {
    var tracker = ModifierTapTracker(key: .control)
    let rightCommandDown: UInt64 = (1 << 20) | 0x10
    let taps = [tap(&tracker, keyCode: 54, down: rightCommandDown, at: 0),
                tap(&tracker, keyCode: 54, down: rightCommandDown, at: 0.2)]
    #expect(taps == [false, false])
}

// MARK: - Notch beim Schreiben

@Test func noteShortcutOpensNotesAndClosesWhenDone() {
    var s = NotchState()
    s.apply(.noteShortcut(pointerInside: false), style: .island)
    #expect(s.mode == .panel(.notes)); #expect(s.isWritingNote)
    // Gespeichert oder Escape: Das Panel gibt die Tastatur ab, die Notch klappt zu.
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .idle); #expect(!s.isWritingNote)
}

@Test func noteWrittenWhileHoveringStaysOpen() {
    var s = NotchState()
    s.apply(.hoverBegan, style: .island); s.apply(.tabSelected(.notes), style: .island)
    // Klick ins Notizfeld: Das Panel bekommt die Tastatur.
    s.apply(.editingBegan, style: .island)
    #expect(s.isWritingNote)
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .panel(.notes))
}

@Test func leavingTheNotchWhileWritingKeepsTheNote() {
    var s = NotchState()
    s.apply(.hoverBegan, style: .island); s.apply(.tabSelected(.notes), style: .island)
    s.apply(.editingBegan, style: .island)
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .panel(.notes))
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .idle)
}

@Test func pointerComingBackWhileWritingKeepsTheNotchOpenAfterwards() {
    var s = NotchState()
    s.apply(.noteShortcut(pointerInside: false), style: .island)
    s.apply(.hoverBegan, style: .island)
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .panel(.notes))
}

@Test func noteWaitsForASignalThatCameMeanwhile() {
    var s = NotchState()
    s.apply(.noteShortcut(pointerInside: false), style: .island)
    s.apply(.signalRaised, style: .island)
    #expect(s.mode == .panel(.notes)); #expect(s.isWritingNote)
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .signal(.island))
}

@Test func noteShortcutDoesNotInterruptAnAnswer() {
    var s = NotchState()
    s.apply(.signalRaised, style: .island); s.apply(.islandClicked, style: .island)
    s.apply(.editingBegan, style: .island)
    s.apply(.noteShortcut(pointerInside: false), style: .island)
    #expect(s.mode == .signal(.banner)); #expect(!s.isWritingNote)
}

@Test func fileDragDoesNotInterruptANote() {
    var s = NotchState()
    s.apply(.noteShortcut(pointerInside: false), style: .island)
    s.apply(.fileDragEntered, style: .island)
    #expect(s.mode == .panel(.notes)); #expect(!s.isReceivingFiles)
}

@Test func switchingTabsEndsTheNote() {
    var s = NotchState()
    s.apply(.noteShortcut(pointerInside: true), style: .island)
    s.apply(.tabSelected(.music), style: .island)
    #expect(!s.isWritingNote); #expect(s.mode == .panel(.music))
}

@Test func notesAreAPanelTab() {
    #expect(PanelTab.allCases.last == .notes)
    #expect(PanelTab.notes.title == "Notizen")
}
