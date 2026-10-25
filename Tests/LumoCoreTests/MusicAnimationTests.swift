import CoreGraphics
import Foundation
import Testing
@testable import LumoCore

@Test func playIsATriangleSplitInTwo() {
    let halves = PlayPauseGeometry.polygons(progress: 0)
    #expect(halves.count == 2 && halves.allSatisfy { $0.count == 4 })
    // Die rechte Hälfte läuft in der Spitze zusammen, die linke steht auf der ganzen Höhe.
    #expect(halves[1][1] == halves[1][2])
    #expect(halves[0][0].y == 0 && halves[0][3].y == 1)
    // Beide Hälften stoßen in der Mitte aneinander.
    #expect(halves[0][1] == halves[1][0] && halves[0][2] == halves[1][3])
}

@Test func pauseIsTwoBars() {
    let bars = PlayPauseGeometry.polygons(progress: 1)
    for bar in bars {
        #expect(bar[0].y == 0 && bar[1].y == 0 && bar[2].y == 1 && bar[3].y == 1)
        #expect(bar[0].x == bar[3].x && bar[1].x == bar[2].x)
    }
    // Zwischen den Balken bleibt eine Lücke.
    #expect(bars[1][0].x - bars[0][1].x > 0.2)
}

@Test func morphInterpolatesAndClamps() {
    let start = PlayPauseGeometry.polygons(progress: 0)
    let end = PlayPauseGeometry.polygons(progress: 1)
    let middle = PlayPauseGeometry.polygons(progress: 0.5)
    #expect(abs(middle[0][1].x - (start[0][1].x + end[0][1].x) / 2) < 1e-9)
    #expect(PlayPauseGeometry.polygons(progress: -2) == start)
    #expect(PlayPauseGeometry.polygons(progress: 7) == end)
}

@Test func coverFlipsInSkipDirection() {
    let t = Date(timeIntervalSince1970: 1_792_700_000)
    #expect(SkipDirection.forTrackChange(lastCommand: .previous, sentAt: t, now: t.addingTimeInterval(1)) == .backward)
    #expect(SkipDirection.forTrackChange(lastCommand: .next, sentAt: t, now: t.addingTimeInterval(1)) == .forward)
    // Ohne (frischen) Befehl ging der Titel von selbst weiter: vorwärts.
    #expect(SkipDirection.forTrackChange(lastCommand: .previous, sentAt: t, now: t.addingTimeInterval(30)) == .forward)
    #expect(SkipDirection.forTrackChange(lastCommand: nil, sentAt: nil, now: t) == .forward)
    #expect(SkipDirection.forTrackChange(lastCommand: .playPause, sentAt: t, now: t) == .forward)
}
