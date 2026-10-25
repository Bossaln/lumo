import CoreGraphics
import Foundation
import Testing
@testable import LumoCore

// MARK: - Ablage

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func newFilesComeFirst() {
    var shelf = Shelf()
    shelf.add(["/a/Bericht.pdf"], now: t0)
    shelf.add(["/b/Foto.jpg", "/b/Notiz.txt"], now: t0 + 5)
    #expect(shelf.items.map(\.path) == ["/b/Foto.jpg", "/b/Notiz.txt", "/a/Bericht.pdf"])
    #expect(shelf.items.first?.name == "Foto.jpg")
}

@Test func droppingAFileAgainMovesItToTheFront() {
    var shelf = Shelf()
    shelf.add(["/a/1.txt", "/a/2.txt"], now: t0)
    let added = shelf.add(["/a/2.txt", "/a/2.txt"], now: t0 + 1)
    #expect(shelf.items.map(\.path) == ["/a/2.txt", "/a/1.txt"])
    #expect(added == ["/a/2.txt"])
    #expect(shelf.items.first?.addedAt == t0 + 1)
}

@Test func shelfKeepsOnlyTheNewestFiles() {
    var shelf = Shelf()
    shelf.add((1...Shelf.limit).map { "/f/\($0)" }, now: t0)
    shelf.add(["/f/neu"], now: t0 + 1)
    #expect(shelf.items.count == Shelf.limit)
    #expect(shelf.items.first?.path == "/f/neu")
    #expect(!shelf.items.contains { $0.path == "/f/\(Shelf.limit)" })
}

@Test func filesCanBeRemovedOneByOneOrAllAtOnce() {
    var shelf = Shelf()
    shelf.add(["/a", "/b", "/c"], now: t0)
    shelf.remove("/b")
    #expect(shelf.items.map(\.path) == ["/a", "/c"])
    shelf.removeAll()
    #expect(shelf.items.isEmpty)
}

@Test func filesThatWereDeletedDisappearFromTheShelf() {
    var shelf = Shelf()
    shelf.add(["/da", "/weg", "/auch-da"], now: t0)
    let changed = shelf.prune { $0 != "/weg" }
    #expect(changed)
    #expect(shelf.items.map(\.path) == ["/da", "/auch-da"])
    let again = shelf.prune { _ in true }
    #expect(!again)
}

@MainActor @Test func shelfSurvivesARestart() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID())/shelf.json")
    let file = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID()).txt")
    try Data("hallo".utf8).write(to: file)
    let store = ShelfStore(fileURL: url)
    store.add([file.path, "/gibt/es/nicht.txt"])
    // Beim Start fallen Dateien heraus, die es nicht mehr gibt.
    #expect(ShelfStore(fileURL: url).shelf.items.map(\.path) == [file.path])
}

@MainActor @Test func unreadableShelfStartsEmpty() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "lumo-\(UUID()).json")
    try Data("{kaputt".utf8).write(to: url)
    #expect(ShelfStore(fileURL: url).shelf.items.isEmpty)
}

// MARK: - Dateien über die Notch ziehen

/// Ergebnisse von `dragged` für eine Folge von (Zähler, Dateien?) nach einem Klick.
private func dragResults(mouseDown: Int?, insideLumo: Bool = false, _ moves: [(Int, Bool)]) -> [Bool] {
    var tracker = FileDragTracker()
    if let mouseDown { tracker.mouseDown(changeCount: mouseDown, insideLumo: insideLumo) }
    return moves.map { tracker.dragged(changeCount: $0.0, hasFiles: $0.1) }
}

@Test func draggingFilesFromAnotherAppIsRecognised() {
    // Ein Fenster verschieben ändert den Drag-Zwischenspeicher nicht; beginnt ein Ziehen mit Dateien,
    // schreibt die Quelle neu hinein.
    #expect(dragResults(mouseDown: 7, [(7, true), (8, true), (8, true)]) == [false, true, true])
    var tracker = FileDragTracker()
    tracker.mouseDown(changeCount: 7, insideLumo: false)
    _ = tracker.dragged(changeCount: 8, hasFiles: true)
    let ended = tracker.mouseUp()
    let endedAgain = tracker.mouseUp()
    #expect(ended && !endedAgain)
    #expect(!tracker.isDraggingFiles)
}

@Test func draggingTextIsNotAFileDrag() {
    #expect(dragResults(mouseDown: 1, [(2, false)]) == [false])
}

@Test func draggingOutOfTheShelfDoesNotOpenTheDropTargets() {
    #expect(dragResults(mouseDown: 3, insideLumo: true, [(4, true)]) == [false])
}

@Test func dragWithoutSeenMouseDownStartsCountingFromThere() {
    #expect(dragResults(mouseDown: nil, [(5, true), (5, true), (6, true)]) == [false, false, true])
}

@Test func dropZoneReachesBeyondTheNotch() {
    let notch = CGRect(x: 662, y: 950, width: 188, height: 32)
    let zone = NotchGeometry.dropZone(around: notch)
    #expect(zone.contains(CGPoint(x: 640, y: 940)))
    #expect(zone.maxY == notch.maxY)
    #expect(zone.minX < notch.minX - 40 && zone.maxX > notch.maxX + 40)
    #expect(!zone.contains(CGPoint(x: 756, y: 850)))
}

// MARK: - Notch

@Test func fileDragOpensTheShelfWithDropTargets() {
    var s = NotchState(); s.lastTab = .music
    s.apply(.fileDragEntered, style: .island)
    #expect(s.mode == .panel(.shelf))
    #expect(s.isReceivingFiles)
    s.apply(.fileDragEnded, style: .island)
    #expect(!s.isReceivingFiles)
    // Die Ablage bleibt offen, bis der Zeiger geht; der gewählte Reiter bleibt der alte.
    #expect(s.mode == .panel(.shelf))
    s.apply(.hoverEnded, style: .island); s.apply(.hoverBegan, style: .island)
    #expect(s.mode == .panel(.music))
}

@Test func fileDragOverASignalReturnsToTheSignal() {
    var s = NotchState(); s.apply(.signalRaised, style: .island)
    s.apply(.fileDragEntered, style: .island)
    #expect(s.mode == .panel(.shelf))
    s.apply(.fileDragEnded, style: .island)
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .signal(.island))
}

@Test func fileDragWhileTypingKeepsTheAnswer() {
    var s = NotchState(); s.apply(.signalRaised, style: .island)
    s.apply(.islandClicked, style: .island)
    s.apply(.editingBegan, style: .island)
    s.apply(.fileDragEntered, style: .island)
    #expect(s.mode == .signal(.banner))
    #expect(!s.isReceivingFiles)
}

@Test func shelfIsAPanelTab() {
    #expect(PanelTab.allCases.contains(.shelf))
    #expect(PanelTab.shelf.title == "Ablage")
}

@Test func collapsingTheNotchForgetsTheDropTargets() {
    // Meldet macOS das Loslassen nicht, zeigt die Ablage beim nächsten Öffnen trotzdem ihre Dateien.
    var s = NotchState()
    s.apply(.fileDragEntered, style: .island)
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .idle)
    #expect(!s.isReceivingFiles)
}

@Test func dragsStartedInLumoAreNotWatched() {
    // Spulen im Musik-Reiter oder eine Datei aus der Ablage ziehen: kein Blick in den Drag-Zwischenspeicher nötig.
    var tracker = FileDragTracker()
    tracker.mouseDown(changeCount: 0, insideLumo: true)
    #expect(!tracker.isWatching)
    tracker.mouseDown(changeCount: 4, insideLumo: false)
    #expect(tracker.isWatching)
    _ = tracker.mouseUp()
    #expect(tracker.isWatching)
}
