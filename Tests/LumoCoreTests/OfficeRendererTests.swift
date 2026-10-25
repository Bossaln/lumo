import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_700_000)

private func agent(_ id: String, _ kind: AgentKind, at point: PixelPoint, activity: OfficeActivity) -> OfficeAgent {
    let session = AgentSession(id: id, agent: kind, sessionId: id, title: "t", projectName: "p", cwd: nil, status: .working,
                               lastStep: nil, errorCount: 0, contextFraction: nil, lastActivity: t0, pending: nil,
                               host: SessionHost(cmuxSurface: nil, originator: nil))
    var a = OfficeAgent(id: id, agent: kind, look: OfficeLook(sessionID: id), position: point, activity: activity,
                        session: session)
    if case .working(let seat) = activity { a.seat = seat; a.facing = OfficeLayout.seats[seat].facing }
    return a
}

private let colors = OfficeRenderer.Colors(claude: RGBA(hex: 0xE0764A), codex: RGBA(hex: 0x8AA2FF))

@Test func workingScreensAnimate() {
    let bg = OfficeArt.background(daylight: 0)
    let worker = agent("a", .claude, at: OfficeLayout.seats[0].sit, activity: .working(seat: 0))
    let a = OfficeRenderer.frame(background: bg, agents: [worker], colors: colors, time: 10)
    let b = OfficeRenderer.frame(background: bg, agents: [worker], colors: colors, time: 11.3)
    let screen = OfficeLayout.seats[0].screen
    var changed = 0
    for y in screen.y..<screen.maxY { for x in screen.x..<screen.maxX where a[x, y] != b[x, y] { changed += 1 } }
    #expect(changed > 0)
    // Ein leerer Platz zeigt einen ruhigen, dunklen Bildschirm.
    let empty = OfficeLayout.seats[1].screen
    var still = 0
    for y in empty.y..<empty.maxY { for x in empty.x..<empty.maxX where a[x, y] != b[x, y] { still += 1 } }
    #expect(still == 0)
}

@Test func charactersAreDrawnInDepthOrder() {
    // Zwei Figuren überlappen: die weiter vorn (größeres y) liegt oben.
    let bg = PixelCanvas(width: OfficeLayout.width, height: OfficeLayout.height, fill: RGBA(0, 0, 0))
    let back = agent("back", .claude, at: PixelPoint(60, 140), activity: .wandering(spot: 0))
    let front = agent("front", .codex, at: PixelPoint(62, 146), activity: .wandering(spot: 1))
    let frame = OfficeRenderer.frame(background: bg, agents: [front, back], colors: colors, time: 0)
    // Ein Pixel am Oberkörper der vorderen Figur hat deren Farbe.
    #expect(frame[59, 134] == RGBA(hex: 0x8AA2FF))
}

@Test func projectionLoops() {
    let bg = OfficeArt.background(daylight: 0)
    let a = OfficeRenderer.frame(background: bg, agents: [], colors: colors, time: 1)
    let b = OfficeRenderer.frame(background: bg, agents: [], colors: colors, time: 1.5)
    let p = OfficeLayout.projection
    var changed = 0
    for y in p.y..<p.maxY { for x in p.x..<p.maxX where a[x, y] != b[x, y] { changed += 1 } }
    #expect(changed > 10)
}
