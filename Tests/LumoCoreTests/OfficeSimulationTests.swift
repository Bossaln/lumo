import Foundation
import Testing
@testable import LumoCore

private let t0 = Date(timeIntervalSince1970: 1_792_700_000)

private func session(_ id: String, _ agent: AgentKind = .claude, _ status: SessionStatus = .working,
                     lastActivity: Date = t0) -> AgentSession {
    AgentSession(id: "\(agent.rawValue):\(id)", agent: agent, sessionId: id, title: "Aufgabe \(id)", projectName: "lumo",
                 cwd: nil, status: status, lastStep: nil, errorCount: 0, contextFraction: nil, lastActivity: lastActivity,
                 pending: nil, host: SessionHost(cmuxSurface: nil, originator: nil))
}

/// Lässt die Simulation laufen, bis alle angekommen sind (oder die Zeit um ist).
private func settle(_ sim: inout OfficeSimulation, from start: Date = t0, seconds: Double = 40) -> Date {
    var now = start
    for _ in 0..<Int(seconds * 10) {
        now = now.addingTimeInterval(0.1)
        sim.step(dt: 0.1, now: now)
    }
    return now
}

@Test func pathAvoidsObstacles() {
    let nav = OfficeNavigator()
    let from = PixelPoint(20, 140), to = PixelPoint(20, 190)  // zwischen den Autos hindurch nach unten
    let path = nav.path(from: from, to: to)
    #expect(!path.isEmpty)
    #expect(path.last == to)
    // Kein Wegpunkt (und kein Zwischenstück) liegt in einem Hindernis.
    var previous = from
    for point in path {
        for k in 0...10 {
            let t = Double(k) / 10
            let x = previous.x + (point.x - previous.x) * t, y = previous.y + (point.y - previous.y) * t
            #expect(!OfficeLayout.obstacles.contains { $0.contains(x, y) } || point == path.last)
        }
        previous = point
    }
}

@Test func workingAgentSitsAtADesk() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    let end = settle(&sim)
    let agent = try! #require(sim.agents.first)
    #expect(agent.activity == .working(seat: 0))
    #expect(agent.isArrived)
    #expect(agent.position == OfficeLayout.seats[0].sit)
    #expect(agent.pose(now: end) == .sitDesk(typing: true) || agent.pose(now: end) == .sitDesk(typing: false))
    #expect(agent.facing == OfficeLayout.seats[0].facing)
}

@Test func seatsAreNotShared() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a"), session("b", .codex), session("c")], now: t0)
    let seats = sim.agents.compactMap(\.seat)
    #expect(Set(seats).count == 3)
}

@Test func waitingAgentStands() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    var now = settle(&sim)
    sim.update(sessions: [session("a", .claude, .waitingApproval)], now: now)
    now = settle(&sim, from: now)
    let agent = try! #require(sim.agents.first)
    #expect(agent.activity == .waiting(seat: 0))
    #expect(agent.position == OfficeLayout.seats[0].stand)
    #expect(agent.pose(now: now) == .stand)
    #expect(agent.bubble == .waiting)
}

@Test func doneAgentFetchesRedBullThenCouch() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    var now = settle(&sim)
    sim.update(sessions: [session("a", .claude, .done, lastActivity: now)], now: now)
    #expect(sim.agents.first?.activity == .fetchingDrink)
    now = settle(&sim, from: now, seconds: 60)
    let agent = try! #require(sim.agents.first)
    #expect(agent.holdsDrink)
    if case .chilling = agent.activity {} else { Issue.record("erwartet Couch, war \(agent.activity)") }
    #expect(OfficeLayout.couchSeats.contains(agent.position))
    #expect(agent.pose(now: now) == .sitCouch(drinking: true))
}

@Test func longIdleAgentSleeps() {
    var sim = OfficeSimulation()
    let long = t0.addingTimeInterval(-20 * 60)
    sim.update(sessions: [session("a", .claude, .ready, lastActivity: long)], now: t0)
    let now = settle(&sim, seconds: 60)
    let agent = try! #require(sim.agents.first)
    if case .sleeping = agent.activity {} else { Issue.record("erwartet Bett, war \(agent.activity)") }
    #expect(agent.pose(now: now) == .lie)
    #expect(agent.bubble == .sleeping)
}

@Test func removedSessionLeavesUpTheStairs() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    var now = settle(&sim)
    sim.update(sessions: [], now: now)
    #expect(sim.agents.first?.activity == .leaving)
    now = settle(&sim, from: now, seconds: 60)
    #expect(sim.agents.isEmpty)
}

@Test func newAgentsComeDownTheStairs() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    #expect(sim.agents.first?.position == OfficeLayout.spawn)
}

@Test func claudeWearsOrangeCodexBlue() {
    let claude = OfficeSprites.outfit(for: .claude, color: RGBA(hex: 0xE0764A))
    let codex = OfficeSprites.outfit(for: .codex, color: RGBA(hex: 0x8AA2FF))
    #expect(claude["B"] == RGBA(hex: 0xE0764A))
    #expect(codex["B"] == RGBA(hex: 0x8AA2FF))
    // Codex trägt eine Cap, Claude eine Kapuze: unterschiedliche Köpfe.
    #expect(OfficeSprites.head(.claude, facing: .down) != OfficeSprites.head(.codex, facing: .down))
}

@Test func walkFramesDiffer() {
    let a = OfficeSprites.rows(agent: .claude, pose: .walk(frame: 0), facing: .right)
    let b = OfficeSprites.rows(agent: .claude, pose: .walk(frame: 1), facing: .right)
    #expect(a != b)
    #expect(OfficeSprites.rows(agent: .codex, pose: .stand, facing: .down).allSatisfy { $0.count == OfficeSprites.width })
}

@Test func appearanceIsStablePerSession() {
    #expect(OfficeLook(sessionID: "claude:abc") == OfficeLook(sessionID: "claude:abc"))
    let looks = Set((0..<40).map { OfficeLook(sessionID: "s\($0)") })
    #expect(looks.count > 4)
}

@Test func headTopFollowsThePose() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a")], now: t0)
    let end = settle(&sim)
    let agent = try! #require(sim.agents.first)
    // Sitzend ist die Figur kleiner als stehend.
    #expect(agent.headTop(now: end) == agent.position.y - 18)
}

@Test func chatterComesAndGoes() {
    var sim = OfficeSimulation()
    sim.update(sessions: [session("a", .claude, .done, lastActivity: t0)], now: t0)
    let end = settle(&sim, seconds: 60)
    let agent = try! #require(sim.agents.first)
    let lines = (0..<60).compactMap { OfficeChatter.line(for: agent, now: end.addingTimeInterval(Double($0))) }
    #expect(!lines.isEmpty && lines.count < 60)  // mal ja, mal nein
    #expect(OfficeChatter.line(for: agent, now: end) == OfficeChatter.line(for: agent, now: end))
    // Wer arbeitet, redet nicht.
    var worker = agent
    worker.activity = .working(seat: 0)
    #expect((0..<60).allSatisfy { OfficeChatter.line(for: worker, now: end.addingTimeInterval(Double($0))) == nil })
}

@Test func doubleTapNeedsTwoQuickPresses() {
    var detector = DoubleTapDetector(window: 0.4)
    let results = [0, 0.25, 0.4, 1.2, 1.5].map { detector.register(at: t0.addingTimeInterval($0)) }
    // Zweiter Druck nach 0,25 s zählt; danach beginnt es von vorn, zu langsam zählt nicht.
    #expect(results == [false, true, false, false, true])
}

// Rohwerte von `NSEvent.modifierFlags`: ⌘ (geräteunabhängig) und das Bit der rechten ⌘-Taste.
private let rightCommandDown: UInt64 = (1 << 20) | 0x10
private let released: UInt64 = 0

/// Drückt und lässt die rechte ⌘-Taste los; gibt zurück, ob das Büro aufgehen soll.
private func tap(_ tracker: inout RightCommandTapTracker, at seconds: Double, hold: Double = 0.1) -> Bool {
    _ = tracker.flagsChanged(keyCode: 54, flags: rightCommandDown, at: t0.addingTimeInterval(seconds))
    return tracker.flagsChanged(keyCode: 54, flags: released, at: t0.addingTimeInterval(seconds + hold))
}

@Test func rightCommandDoubleTapOpensOffice() {
    var tracker = RightCommandTapTracker()
    let first = tap(&tracker, at: 0)
    let second = tap(&tracker, at: 0.25)
    #expect(!first)
    #expect(second)
}

@Test func rightCommandShortcutDoesNotCount() {
    var tracker = RightCommandTapTracker()
    _ = tap(&tracker, at: 0)
    // ⌘C mit der rechten ⌘-Taste: Dazwischen kommt eine andere Taste.
    _ = tracker.flagsChanged(keyCode: 54, flags: rightCommandDown, at: t0.addingTimeInterval(0.2))
    tracker.keyDown()
    let result = tracker.flagsChanged(keyCode: 54, flags: released, at: t0.addingTimeInterval(0.3))
    #expect(!result)
}

@Test func rightCommandLongHoldOrOtherModifierDoesNotCount() {
    var tracker = RightCommandTapTracker()
    _ = tap(&tracker, at: 0)
    let held = tap(&tracker, at: 0.2, hold: 0.6)
    #expect(!held)
    var withShift = RightCommandTapTracker()
    _ = tap(&withShift, at: 0)
    // ⇧ ist schon gedrückt, als die rechte ⌘-Taste kommt.
    _ = withShift.flagsChanged(keyCode: 54, flags: rightCommandDown | (1 << 17), at: t0.addingTimeInterval(0.2))
    let shifted = withShift.flagsChanged(keyCode: 54, flags: 1 << 17, at: t0.addingTimeInterval(0.3))
    #expect(!shifted)
}

@Test func leftCommandDoesNotCount() {
    var tracker = RightCommandTapTracker()
    let leftDown: UInt64 = (1 << 20) | 0x08
    let results = [0.0, 0.2].map { s -> Bool in
        _ = tracker.flagsChanged(keyCode: 55, flags: leftDown, at: t0.addingTimeInterval(s))
        return tracker.flagsChanged(keyCode: 55, flags: released, at: t0.addingTimeInterval(s + 0.1))
    }
    #expect(results == [false, false])
}
