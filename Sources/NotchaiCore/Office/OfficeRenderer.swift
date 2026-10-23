import Foundation

/// Bewegte Ebene der Halle, je Bild neu: Bildschirme, Projektion, Beamer-Strahl, blinkende Lämpchen und die
/// Figuren (in Tiefe sortiert). Der Hintergrund kommt fertig aus `OfficeArt`.
public enum OfficeRenderer {
    /// Agentenfarben aus den Einstellungen (Hoodie bzw. Jacke).
    public struct Colors: Equatable, Sendable {
        public var claude: RGBA
        public var codex: RGBA

        public init(claude: RGBA, codex: RGBA) {
            self.claude = claude
            self.codex = codex
        }

        func color(for agent: AgentKind) -> RGBA { agent == .claude ? claude : codex }
    }

    public static func frame(background: PixelCanvas, agents: [OfficeAgent], colors: Colors, time: Double) -> PixelCanvas {
        var c = background
        let now = Date(timeIntervalSinceReferenceDate: time)
        drawScreens(&c, agents: agents, time: time)
        drawProjection(&c, time: time)
        drawBeam(&c)
        drawLEDs(&c, time: time)
        for agent in agents.sorted(by: { $0.position.y < $1.position.y }) {
            OfficeSprites.draw(&c, agent: agent.agent, look: agent.look,
                               outfit: OfficeSprites.outfit(for: agent.agent, color: colors.color(for: agent.agent)),
                               pose: agent.pose(now: now), facing: agent.facing, at: agent.position)
        }
        return c
    }

    // MARK: Bildschirme

    /// Schräge Bildschirmfläche eines Platzes (wie im Tischblock gezeichnet).
    static func screenQuad(_ seat: OfficeSeat) -> [(Double, Double)] {
        let x = Double(seat.screen.x), y = Double(seat.screen.y)
        return seat.facing == .right
            ? [(x, y + 1), (x + 6, y), (x + 6, y + 14), (x, y + 12)]
            : [(x, y), (x + 6, y + 1), (x + 6, y + 12), (x, y + 14)]
    }

    static func drawScreens(_ c: inout PixelCanvas, agents: [OfficeAgent], time: Double) {
        for seat in OfficeLayout.seats {
            guard let occupant = agents.first(where: { $0.seat == seat.index && $0.isArrived }) else { continue }
            var mask = PixelCanvas(width: 8, height: 16)
            let quad = screenQuad(seat).map { ($0.0 - Double(seat.screen.x) + 1, $0.1 - Double(seat.screen.y) + 1) }
            mask.polygon(quad, RGBA(255, 255, 255))
            // Rand innen frei lassen, damit der Rahmen sichtbar bleibt.
            func inside(_ x: Int, _ y: Int) -> Bool {
                mask[x + 1, y + 1].a > 0 && mask[x, y + 1].a > 0 && mask[x + 2, y + 1].a > 0
                    && mask[x + 1, y].a > 0 && mask[x + 1, y + 2].a > 0
            }
            let base: RGBA
            switch occupant.activity {
            case .working: base = RGBA(hex: 0x0D1B2E)
            case .failed: base = RGBA(hex: 0x4A0D14)
            case .waiting: base = RGBA(hex: 0x3D2A06)
            default: continue
            }
            let scroll = Int(time * 3)
            for dy in 0..<15 {
                for dx in 0..<7 where inside(dx, dy) {
                    var color = base
                    if case .working = occupant.activity, dy % 2 == 1 {
                        // Code-Zeilen: Einrückung und Länge wechseln, die Zeilen laufen nach oben.
                        let line = dy / 2 + scroll
                        let indent = Int(OfficeArt.noise(seat.index, line) * 3)
                        let length = 2 + Int(OfficeArt.noise(line, seat.index + 9) * 4)
                        if dx >= indent && dx < indent + length {
                            let palette: [UInt32] = [0x7EE787, 0x79C0FF, 0xFF7B72, 0xD2A8FF, 0xE6EDF3]
                            color = RGBA(hex: palette[Int(OfficeArt.noise(line, dx) * 5) % 5])
                        }
                    } else if case .failed = occupant.activity, (dx + dy) % 4 == 0 {
                        color = RGBA(hex: 0xFF4D5E)
                    } else if case .waiting = occupant.activity, dy == 6 || dy == 7 {
                        color = RGBA(hex: 0xFFC53D)
                    }
                    c.replace(seat.screen.x + dx - 1, seat.screen.y + dy - 1, color)
                }
            }
        }
    }

    // MARK: Projektion

    /// Synthwave-Schleife auf der Rückwand: Abendhimmel, gestreifte Sonne, laufendes Gitter, kleines Auto.
    static func drawProjection(_ c: inout PixelCanvas, time: Double) {
        let p = OfficeLayout.projection
        // Eigener Puffer: Linien und Auto bleiben in der Projektionsfläche.
        var img = PixelCanvas(width: p.w, height: p.h)
        let horizon = 12
        let sky0 = RGBA(hex: 0x2A0B45), sky1 = RGBA(hex: 0xFF5E9A)
        for y in 0..<p.h {
            for x in 0..<p.w {
                var color: RGBA
                if y < horizon {
                    color = sky0.mixed(with: sky1, Double(y) / Double(horizon))
                    // Sonne: halbe Scheibe mit Streifen.
                    let dx = Double(x) - Double(p.w) / 2 + 0.5, dy = Double(y) - Double(horizon) + 0.5
                    if dx * dx + dy * dy < 64 && !(y == horizon - 3 || y == horizon - 5) {
                        color = RGBA(hex: 0xFFD34D).mixed(with: RGBA(hex: 0xFF4F8B), Double(y) / Double(horizon))
                    }
                } else {
                    color = RGBA(hex: 0x160A28)
                }
                img.replace(x, y, color)
            }
        }
        img.hline(0, horizon, p.w, RGBA(hex: 0xFF7AC0))
        let grid = RGBA(hex: 0xC2368C)
        let vx = p.w / 2
        for k in -6...6 {
            img.line(vx, horizon, vx + k * 9, p.h - 1, grid)
        }
        let phase = (time * 0.6).truncatingRemainder(dividingBy: 1)
        for k in 0..<5 {
            let t = (Double(k) / 5 + phase).truncatingRemainder(dividingBy: 1)
            img.hline(0, horizon + 1 + Int(t * t * Double(p.h - horizon - 2)), p.w, grid)
        }
        // Kleines pinkes Auto mit Rücklichtern fährt mittig davon.
        let bounce = Int((time * 4).truncatingRemainder(dividingBy: 2))
        let carX = vx - 4, carY = p.h - 6 - bounce
        img.fill(carX, carY, 8, 3, RGBA(hex: 0xFF4FA3))
        img.fill(carX + 1, carY - 1, 6, 1, RGBA(hex: 0x2A0B45))
        img.set(carX, carY + 1, RGBA(hex: 0xFF2A2A))
        img.set(carX + 7, carY + 1, RGBA(hex: 0xFF2A2A))
        c.draw(img, at: p.x, p.y)
        c.frame(p.x - 1, p.y - 1, p.w + 2, p.h + 2, RGBA(hex: 0x1A1A1E))
    }

    /// Ganz zarter Lichtkegel vom Beamer über dem Bett zur Projektion an der Rückwand.
    static func drawBeam(_ c: inout PixelCanvas) {
        let lens = OfficeLayout.projector
        let p = OfficeLayout.projection
        c.polygon([(Double(lens.x + 4), Double(lens.y + 4)), (Double(p.x), Double(p.maxY)), (Double(p.maxX), Double(p.maxY))],
                  RGBA(255, 210, 240, 14))
    }

    /// Blinkende Lämpchen am Server-Regal auf der Galerie.
    static func drawLEDs(_ c: inout PixelCanvas, time: Double) {
        let tick = Int(time * 3)
        for row in 0..<4 {
            for col in 0..<3 {
                let on = OfficeArt.noise(row * 3 + col, tick / (1 + col)) > 0.45
                let color = col == 2 ? RGBA(hex: 0x4DA3FF) : RGBA(hex: 0x44E07A)
                c.set(304 + col * 3, 18 + row * 3, on ? color : RGBA(hex: 0x1C2A22))
            }
        }
    }
}
