import Foundation

/// Was eine Figur gerade tut (aus dem Status ihrer Session).
public enum OfficeActivity: Equatable, Sendable {
    /// Arbeitet am Tisch und tippt.
    case working(seat: Int)
    /// Wartet auf den Besitzer: steht neben ihrem Platz.
    case waiting(seat: Int)
    /// Fehler: sitzt am Tisch, rote Blase.
    case failed(seat: Int)
    /// Fertig: holt sich ein Red Bull aus dem Kühlschrank …
    case fetchingDrink
    /// … und trinkt es auf der Couch.
    case chilling(spot: Int)
    /// Lange untätig: schläft im Bett.
    case sleeping(spot: Int)
    /// Kein Platz frei: steht in der Halle herum.
    case wandering(spot: Int)
    /// Session ist weg: geht die Treppe hinauf und verschwindet.
    case leaving
}

/// Sprechblase über einer Figur (Text zeigt die App).
public enum OfficeBubble: Equatable, Sendable { case waiting, error, sleeping }

/// Eine Figur in der Halle.
public struct OfficeAgent: Equatable, Sendable, Identifiable {
    public var id: String
    public var agent: AgentKind
    public var look: OfficeLook
    public var position: PixelPoint
    public var path: [PixelPoint] = []
    public var facing: Facing = .down
    public var activity: OfficeActivity
    public var seat: Int?
    public var holdsDrink = false
    public var walkPhase: Double = 0
    /// Ankunft am Kühlschrank (danach kurz stehen, dann zur Couch).
    var fridgeArrival: Date?
    /// Session-Angaben für Namensschild und Hover-Karte.
    public var session: AgentSession

    public var isArrived: Bool { path.isEmpty }

    /// Haltung zum Zeitpunkt `now` (Tippen wechselt alle 0,15 s).
    public func pose(now: Date) -> OfficePose {
        if !path.isEmpty { return .walk(frame: Int(walkPhase) % 2) }
        switch activity {
        case .working:
            let tick = Int(now.timeIntervalSinceReferenceDate / 0.15)
            return .sitDesk(typing: (tick + id.utf8.count) % 2 == 0)
        case .failed: return .sitDesk(typing: false)
        case .chilling: return .sitCouch(drinking: holdsDrink)
        case .sleeping: return .lie
        case .waiting, .fetchingDrink, .wandering, .leaving: return .stand
        }
    }

    /// Oberkante des Kopfes (für Namensschild und Sprechblase).
    public func headTop(now: Date) -> Double {
        position.y - Double(OfficeSprites.rows(agent: agent, pose: pose(now: now), facing: facing).count)
    }

    public var bubble: OfficeBubble? {
        switch activity {
        case .waiting: .waiting
        case .failed: .error
        case .sleeping where isArrived: .sleeping
        default: nil
        }
    }
}

/// Die Figuren der Halle, gesteuert von den Sessions.
/// - `update(sessions:now:)` setzt für jede Session ein Ziel (Tisch, neben dem Tisch, Kühlschrank → Couch, Bett).
/// - `step(dt:now:)` bewegt die Figuren auf ihren Wegen.
public struct OfficeSimulation: Sendable {
    /// Ab so langer Untätigkeit geht eine fertige Figur ins Bett.
    public static let sleepAfter: TimeInterval = 10 * 60
    /// Gehgeschwindigkeit in Pixeln je Sekunde.
    public static let speed = 30.0
    /// So lange steht eine Figur am Kühlschrank.
    public static let fridgePause: TimeInterval = 1.6

    public private(set) var agents: [OfficeAgent] = []
    let navigator = OfficeNavigator()

    static let wanderSpots = [PixelPoint(120, 192), PixelPoint(196, 196), PixelPoint(100, 236), PixelPoint(206, 240),
                              PixelPoint(60, 136), PixelPoint(160, 100)]

    public init() {}

    public mutating func update(sessions: [AgentSession], now: Date) {
        let ids = Set(sessions.map(\.id))
        for i in agents.indices where !ids.contains(agents[i].id) && agents[i].activity != .leaving {
            setActivity(i, .leaving)
        }
        for session in sessions {
            if let i = agents.firstIndex(where: { $0.id == session.id }) {
                agents[i].session = session
                let desired = desiredActivity(for: agents[i], session: session, now: now)
                if desired != agents[i].activity { setActivity(i, desired) }
            } else {
                var agent = OfficeAgent(id: session.id, agent: session.agent, look: OfficeLook(sessionID: session.id),
                                        position: OfficeLayout.spawn, activity: .leaving, session: session)
                agents.append(agent)
                let i = agents.count - 1
                agent = agents[i]
                setActivity(i, desiredActivity(for: agent, session: session, now: now))
            }
        }
    }

    public mutating func step(dt: Double, now: Date) {
        var remove: [String] = []
        for i in agents.indices {
            var budget = Self.speed * dt
            while budget > 0, let next = agents[i].path.first {
                let pos = agents[i].position
                let d = pos.distance(to: next)
                if d <= budget {
                    agents[i].position = next
                    agents[i].path.removeFirst()
                    budget -= d
                } else {
                    let t = budget / d
                    agents[i].position = PixelPoint(pos.x + (next.x - pos.x) * t, pos.y + (next.y - pos.y) * t)
                    budget = 0
                }
                let dx = next.x - pos.x, dy = next.y - pos.y
                if abs(dx) > 0.01 || abs(dy) > 0.01 {
                    agents[i].facing = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                }
            }
            if !agents[i].path.isEmpty { agents[i].walkPhase += dt * 6 }
            guard agents[i].path.isEmpty else { continue }
            arrive(i, now: now, remove: &remove)
        }
        agents.removeAll { remove.contains($0.id) }
    }

    // MARK: Ziele

    func desiredActivity(for agent: OfficeAgent, session: AgentSession, now: Date) -> OfficeActivity {
        switch session.status {
        case .working:
            return seat(for: agent).map { .working(seat: $0) } ?? .wandering(spot: wanderSpot(for: agent))
        case .waitingApproval, .waitingAnswer:
            return seat(for: agent).map { .waiting(seat: $0) } ?? .wandering(spot: wanderSpot(for: agent))
        case .error:
            return seat(for: agent).map { .failed(seat: $0) } ?? .wandering(spot: wanderSpot(for: agent))
        case .done, .ready:
            if now.timeIntervalSince(session.lastActivity) >= Self.sleepAfter {
                if case .sleeping = agent.activity { return agent.activity }
                if let spot = freeSpot(OfficeLayout.bedSpots.count, taken: { if case .sleeping(let s) = $0 { s } else { nil } }) {
                    return .sleeping(spot: spot)
                }
            }
            switch agent.activity {
            case .fetchingDrink, .chilling, .sleeping: return agent.activity
            default: return .fetchingDrink
            }
        }
    }

    /// Jede Session behält ihren Platz am Tisch, solange es sie gibt.
    func seat(for agent: OfficeAgent) -> Int? {
        if let seat = agent.seat { return seat }
        let taken = Set(agents.compactMap(\.seat))
        return OfficeLayout.seats.map(\.index).first { !taken.contains($0) }
    }

    func wanderSpot(for agent: OfficeAgent) -> Int {
        if case .wandering(let spot) = agent.activity { return spot }
        return freeSpot(Self.wanderSpots.count, taken: { if case .wandering(let s) = $0 { s } else { nil } }) ?? 0
    }

    func freeSpot(_ count: Int, taken: (OfficeActivity) -> Int?) -> Int? {
        let used = Set(agents.compactMap { taken($0.activity) })
        return (0..<count).first { !used.contains($0) }
    }

    mutating func setActivity(_ i: Int, _ activity: OfficeActivity) {
        agents[i].activity = activity
        agents[i].fridgeArrival = nil
        switch activity {
        case .working(let seat), .waiting(let seat), .failed(let seat): agents[i].seat = seat
        case .fetchingDrink: agents[i].holdsDrink = false
        default: break
        }
        agents[i].path = navigator.path(from: agents[i].position, to: target(of: activity))
    }

    func target(of activity: OfficeActivity) -> PixelPoint {
        switch activity {
        case .working(let seat), .failed(let seat): OfficeLayout.seats[seat].sit
        case .waiting(let seat): OfficeLayout.seats[seat].stand
        case .fetchingDrink: OfficeLayout.fridgeSpot
        case .chilling(let spot): OfficeLayout.couchSeats[spot]
        case .sleeping(let spot): OfficeLayout.bedSpots[spot]
        case .wandering(let spot): Self.wanderSpots[spot]
        case .leaving: OfficeLayout.spawn
        }
    }

    /// Angekommen: Blickrichtung setzen, am Kühlschrank kurz warten, Gehende verschwinden lassen.
    mutating func arrive(_ i: Int, now: Date, remove: inout [String]) {
        switch agents[i].activity {
        case .working(let seat), .failed(let seat):
            agents[i].facing = OfficeLayout.seats[seat].facing
        case .waiting, .chilling, .wandering, .sleeping:
            agents[i].facing = .down
        case .fetchingDrink:
            agents[i].facing = .up
            if agents[i].fridgeArrival == nil { agents[i].fridgeArrival = now }
            if let arrival = agents[i].fridgeArrival, now.timeIntervalSince(arrival) >= Self.fridgePause {
                agents[i].holdsDrink = true
                let spot = freeSpot(OfficeLayout.couchSeats.count, taken: { if case .chilling(let s) = $0 { s } else { nil } })
                let next: OfficeActivity = spot.map { .chilling(spot: $0) } ?? .wandering(spot: wanderSpot(for: agents[i]))
                let drink = agents[i].holdsDrink
                setActivity(i, next)
                agents[i].holdsDrink = drink
            }
        case .leaving:
            remove.append(agents[i].id)
        }
    }
}

/// Gelegentliche Sprüche entspannter Figuren.
public enum OfficeChatter {
    static let lines = [
        "Noch ein Red Bull?", "Läuft bei dir?", "Hast du's getestet?", "Deploy am Freitag?", "Kurz durchatmen.",
        "Wer fährt den GT-R?", "Merge-Konflikt?", "Ich mach nur kurz Pause.", "Gleich weiter.", "Der 911 ist frisch poliert.",
    ]
    static let cycle: TimeInterval = 14
    static let visible: TimeInterval = 4

    /// Spruch zum Zeitpunkt `now` oder `nil`: alle 14 s für 4 s, nur auf der Couch.
    public static func line(for agent: OfficeAgent, now: Date) -> String? {
        guard case .chilling = agent.activity, agent.isArrived else { return nil }
        var hash: UInt64 = 1469598103934665603
        for byte in agent.id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let t = now.timeIntervalSinceReferenceDate + Double(hash % 1000) / 1000 * cycle
        guard t.truncatingRemainder(dividingBy: cycle) < visible else { return nil }
        let round = Int(t / cycle)
        return lines[(round + Int(hash % 97)) % lines.count]
    }
}
