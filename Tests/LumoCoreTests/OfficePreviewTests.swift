import Foundation
import Testing
@testable import LumoCore

/// Schreibt Vorschaubilder der Halle als PPM, nur wenn `LUMO_RENDER` auf einen Ordner zeigt
/// (zum Anschauen beim Entwickeln; im normalen Testlauf übersprungen).
private let renderDirectory = ProcessInfo.processInfo.environment["LUMO_RENDER"]

func writePPM(_ canvas: PixelCanvas, to path: String) throws {
    var data = Data("P6\n\(canvas.width) \(canvas.height)\n255\n".utf8)
    for p in canvas.pixels { data.append(contentsOf: [p.r, p.g, p.b]) }
    try data.write(to: URL(fileURLWithPath: path))
}

@Test(.enabled(if: renderDirectory != nil)) func renderOfficePreview() throws {
    let dir = try #require(renderDirectory)
    try writePPM(OfficeArt.background(daylight: 0), to: dir + "/office-night.ppm")
    try writePPM(OfficeArt.background(daylight: 1), to: dir + "/office-day.ppm")
}

@Test(.enabled(if: renderDirectory != nil)) func renderOfficeWithAgents() throws {
    let dir = try #require(renderDirectory)
    let t0 = Date(timeIntervalSince1970: 1_792_700_000)
    func s(_ id: String, _ agent: AgentKind, _ status: SessionStatus, idle: Double = 0) -> AgentSession {
        AgentSession(id: id, agent: agent, sessionId: id, title: id, projectName: "p", cwd: nil, status: status, lastStep: nil,
                     errorCount: 0, contextFraction: nil, lastActivity: t0.addingTimeInterval(-idle), pending: nil,
                     host: SessionHost(cmuxSurface: nil, originator: nil))
    }
    var sim = OfficeSimulation()
    sim.update(sessions: [s("a", .claude, .working), s("b", .codex, .working), s("c", .claude, .working),
                          s("d", .codex, .working), s("e", .claude, .ready, idle: 3600)], now: t0)
    var now = t0
    for _ in 0..<400 { now = now.addingTimeInterval(0.1); sim.step(dt: 0.1, now: now) }
    sim.update(sessions: [s("a", .claude, .working), s("b", .codex, .working), s("c", .claude, .waitingApproval),
                          s("d", .codex, .done), s("e", .claude, .ready, idle: 3600)], now: now)
    for _ in 0..<600 { now = now.addingTimeInterval(0.1); sim.step(dt: 0.1, now: now) }
    let colors = OfficeRenderer.Colors(claude: RGBA(hex: 0xE0764A), codex: RGBA(hex: 0x8AA2FF))
    let frame = OfficeRenderer.frame(background: OfficeArt.background(daylight: 0), agents: sim.agents, colors: colors,
                                     time: now.timeIntervalSinceReferenceDate)
    try writePPM(frame, to: dir + "/office-agents.ppm")
    // Figuren-Bogen: alle Haltungen nebeneinander.
    var sheet = PixelCanvas(width: 200, height: 40, fill: RGBA(hex: 0x2B2B33))
    var x = 8.0
    for agent in [AgentKind.claude, .codex] {
        let outfit = OfficeSprites.outfit(for: agent, color: colors.color(for: agent))
        for (pose, facing) in [(OfficePose.stand, Facing.down), (.stand, .up), (.walk(frame: 0), .right), (.walk(frame: 1), .left),
                               (.sitDesk(typing: true), .right), (.sitCouch(drinking: true), .down), (.lie, .down)] {
            OfficeSprites.draw(&sheet, agent: agent, look: OfficeLook(sessionID: "x"), outfit: outfit, pose: pose,
                               facing: facing, at: PixelPoint(x, 32))
            x += pose == .lie ? 22 : 13
        }
    }
    try writePPM(sheet, to: dir + "/office-sprites.ppm")
}
