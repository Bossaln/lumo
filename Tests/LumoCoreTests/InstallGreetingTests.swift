import Testing
@testable import LumoCore

/// Sichtbarer Text eines Bildes: Farb- und Cursor-Codes entfernt, in Zeilen.
private func visibleLines(_ text: String) -> [String] {
    text.replacing(/\u{1B}\[[0-9;?]*[A-Za-z]/, with: "")
        .replacing("\r", with: "")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

@Test func greetingHidesTheCursorAndShowsItAgainAtTheEnd() {
    let frames = InstallGreeting.frames(columns: 100)
    #expect(frames.first?.text.hasPrefix("\u{1B}[?25l") == true)
    #expect(frames.last?.text.hasSuffix("\u{1B}[?25h") == true)
    // Jedes weitere Bild springt an den Anfang des vorigen zurück.
    #expect(frames.dropFirst().allSatisfy { $0.text.hasPrefix("\u{1B}[\(InstallGreeting.rows - 1)A\u{1B}[1G") })
}

@Test func sceneTellsTheStoryInOrder() {
    let frames = InstallGreeting.frames(columns: 100).map { visibleLines($0.text).joined(separator: "\n") }
    func first(where part: String) -> Int? { frames.firstIndex { $0.contains(part) } }
    let laptop = first(where: "╰"), ring = first(where: "░"), ask = first(where: L("Möchte ausführen:")),
        done = first(where: "✓ " + L("Fertig")), music = first(where: "♪"), text = first(where: InstallGreeting.doneText)
    #expect(laptop != nil && ring != nil && ask != nil && done != nil && music != nil && text != nil)
    if let laptop, let ring, let ask, let done, let music, let text {
        #expect(laptop < ring && ring < ask && ask < done && done < music && music < text)
    }
    // Das MacBook bleibt bis zum Schluss stehen, die Musik läuft weiter, die Insel ist zu.
    #expect(frames.last?.contains("╰") == true)
    #expect(frames.last?.contains("♪") == true)
    #expect(frames.last?.contains("Claude Code") == false)
    #expect(frames.last?.contains(InstallGreeting.tipText) == true)
    #expect(frames.last?.contains(InstallGreeting.supportText) == true)
}

@Test func signalShowsBothButtonsAndTheCommand() {
    let frames = InstallGreeting.frames(columns: 100).map { visibleLines($0.text).joined(separator: "\n") }
    let ask = frames.first { $0.contains(L("Möchte ausführen:")) }
    #expect(ask?.contains("npm test") == true)
    #expect(ask?.contains(L("Ablehnen")) == true && ask?.contains(L("Erlauben")) == true)
    #expect(ask?.contains("Claude Code") == true)
}

@Test func greetingNeverWritesPastTheTerminalEdge() {
    for columns in [50, 72, 80, 133] {
        for frame in InstallGreeting.frames(columns: columns) {
            for line in visibleLines(frame.text) {
                #expect(line.count <= columns - 1, "Spalten \(columns): \(line)")
            }
        }
    }
}

@Test func everyFrameHasTheSameHeight() {
    for frame in InstallGreeting.frames(columns: 80) {
        #expect(visibleLines(frame.text).filter { !$0.isEmpty || true }.count >= InstallGreeting.rows)
    }
}

@Test func narrowTerminalsGetTheSmallestScene() {
    // Die Unterkante des MacBooks reicht über die ganze kleinste Breite.
    let base = visibleLines(InstallGreeting.frames(columns: 20).last!.text).first { $0.hasPrefix("╰") }
    #expect(base?.count == 49)
}

@Test func fullscreenNeedsEnoughRowsAndRestoresTheScreen() {
    #expect(InstallGreeting.fullscreenFrames(columns: 100, rows: InstallGreeting.rows + 1) == nil)
    let fullscreen = InstallGreeting.fullscreenFrames(columns: 100, rows: 40)
    #expect(fullscreen?.frames.first?.text.hasPrefix("\u{1B}[?1049h") == true)
    // Jedes Bild beginnt mittig auf der Seite: (40 − 15) / 2 + 1 = Zeile 13.
    #expect(fullscreen?.frames.allSatisfy { $0.text.contains("\u{1B}[\((40 - InstallGreeting.rows) / 2 + 1);1H") } == true)
    #expect(fullscreen?.closing.hasPrefix("\u{1B}[?1049l") == true)
    #expect(fullscreen?.closing.contains(InstallGreeting.doneText) == true)
    #expect(fullscreen?.closing.contains(InstallGreeting.supportText) == true)
}

@Test func greetingIsNotTooLong() {
    let total = InstallGreeting.frames(columns: 120).map(\.pause).reduce(0, +)
    #expect(total > 5 && total < 12)
}

@Test func plainGreetingHasNoEscapeCodes() {
    #expect(!InstallGreeting.plain.contains("\u{1B}"))
    #expect(InstallGreeting.plain.contains(InstallGreeting.doneText))
}

// Beim Update über den Knopf läuft brew in lumo; die Szene landete sonst Bild für Bild im Protokoll.
private let processes: [Int32: (parent: Int32, name: String)] = [
    900: (1, "lumo"), 901: (900, "zsh"), 902: (901, "ruby"), 903: (902, "lumo-welcome"),
    800: (1, "Terminal"), 801: (800, "zsh"), 802: (801, "ruby"), 803: (802, "lumo-welcome"),
]

@Test func greetingKnowsWhenLumoRunsTheUpdate() {
    #expect(InstallGreeting.isRunByLumo(pid: 903) { processes[$0] })
    #expect(!InstallGreeting.isRunByLumo(pid: 803) { processes[$0] })
    // Unbekannte Prozesse oder eine Schleife beenden die Suche.
    #expect(!InstallGreeting.isRunByLumo(pid: 5) { processes[$0] })
    #expect(!InstallGreeting.isRunByLumo(pid: 7) { _ in (7, "zsh") })
}
