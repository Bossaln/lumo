import Testing
@testable import NotchaiCore

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
}

@Test func carStartsLeftAndDrivesOffToTheRight() {
    let frames = InstallGreeting.frames(columns: 100)
    let first = visibleLines(frames[0].text)
    // Der Wagen beginnt zwei Spalten vom Rand, sein Dach 14 Zeichen weiter.
    let roof = first.first { $0.contains("_______") }
    #expect(roof?.firstIndex(of: "_").map { roof!.distance(from: roof!.startIndex, to: $0) } == 16)
    // Im letzten Bild ist der Wagen weg, übrig bleiben Straße und Satz.
    let last = visibleLines(frames[frames.count - 1].text)
    #expect(!last.contains { $0.contains("___") || $0.contains("|") })
    #expect(last.contains { $0.contains(InstallGreeting.doneText) })
}

@Test func greetingNeverWritesPastTheTerminalEdge() {
    for columns in [50, 80, 133] {
        for frame in InstallGreeting.frames(columns: columns) {
            for line in visibleLines(frame.text) {
                #expect(line.count <= columns - 1, "Spalten \(columns): \(line)")
            }
        }
    }
}

@Test func narrowTerminalsGetTheSmallestRoad() {
    let road = visibleLines(InstallGreeting.frames(columns: 20)[0].text).first { $0.contains("----") }
    #expect(road?.count == 49)
}

@Test func greetingIsShort() {
    let total = InstallGreeting.frames(columns: 120).map(\.pause).reduce(0, +)
    #expect(total > 1 && total < 6)
}

@Test func plainGreetingHasNoEscapeCodes() {
    #expect(!InstallGreeting.plain.contains("\u{1B}"))
    #expect(InstallGreeting.plain.contains(InstallGreeting.doneText))
}
