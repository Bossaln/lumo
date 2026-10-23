import Foundation

/// Ein festes Möbelstück als eigener kleiner Puffer. Steht eine Figur dahinter (ihr Fußpunkt liegt höher als
/// `baseline`), wird es nach der Figur noch einmal gezeichnet und verdeckt sie richtig.
public struct OfficeProp: Sendable {
    public var name: String
    public var x: Int
    public var y: Int
    public var canvas: PixelCanvas
    public var baseline: Int

    public var frame: PixelRect { PixelRect(x: x, y: y, w: canvas.width, h: canvas.height) }
}

/// Zeichnet die Lagerhalle im Code (Konzept: keine fertigen Grafiken). Hintergrund einmal je Tageslicht,
/// bewegte Teile übernimmt `OfficeRenderer`.
public enum OfficeArt {
    // MARK: Farben

    static let steelDark = RGBA(hex: 0x23262C)
    static let steel = RGBA(hex: 0x2E3239)
    static let steelLight = RGBA(hex: 0x3D424B)
    static let steelEdge = RGBA(hex: 0x555C68)
    static let brickA = RGBA(hex: 0x3C2925)
    static let brickB = RGBA(hex: 0x45302A)
    static let brickC = RGBA(hex: 0x352420)
    static let mortar = RGBA(hex: 0x221816)
    static let marbleBase = RGBA(hex: 0x16161B)
    static let marbleMid = RGBA(hex: 0x1D1D24)
    static let marbleVein = RGBA(hex: 0x34343E)
    static let marbleVeinLight = RGBA(hex: 0x4D4D59)
    static let wood = RGBA(hex: 0x5B3A29)
    static let woodLight = RGBA(hex: 0x7A4E36)
    static let woodDark = RGBA(hex: 0x3E271C)
    static let black = RGBA(hex: 0x111114)
    static let shadow = RGBA(0, 0, 0, 90)

    // MARK: Hintergrund

    /// Boden, Wände, Galerie, Treppe und alle Möbel. `daylight` 0 = Nacht, 1 = Tag (Fensterglas).
    public static func background(daylight: Double) -> PixelCanvas {
        var c = PixelCanvas(width: OfficeLayout.width, height: OfficeLayout.height, fill: marbleBase)
        drawFloor(&c)
        drawUpperWall(&c, daylight: daylight)
        drawGallery(&c)
        drawBrickWall(&c)
        drawRollerDoor(&c)
        drawStairs(&c)
        drawNeon(&c)
        drawProjectionSurface(&c)
        drawSideWalls(&c)
        drawRug(&c)
        for prop in props() { c.draw(prop.canvas, at: prop.x, prop.y) }
        return c
    }

    /// Möbel, die Figuren verdecken können (Reihenfolge = Zeichenreihenfolge im Hintergrund).
    public static func props() -> [OfficeProp] {
        [
            fridgeProp(), carProp(gtr: true), carProp(gtr: false), tiresProp(), deskBlockProp(), couchProp(),
            tableProp(), floorLampProp(), bedProp(), projectorProp(), plantProp(), poolTableProp(),
        ]
    }

    // MARK: Boden: dunkler Marmor mit welligen Adern

    static func drawFloor(_ c: inout PixelCanvas) {
        for y in OfficeLayout.floorTop..<OfficeLayout.height {
            for x in 0..<OfficeLayout.width {
                c.replace(x, y, marble(x, y))
            }
        }
        // Fugen der großen Platten (32 px), kaum sichtbar.
        let seam = RGBA(0, 0, 0, 40)
        for x in stride(from: 6, to: OfficeLayout.width, by: 48) { c.vline(x, OfficeLayout.floorTop, OfficeLayout.height, seam) }
        for y in stride(from: OfficeLayout.floorTop + 30, to: OfficeLayout.height, by: 48) { c.hline(0, y, OfficeLayout.width, seam) }
    }

    /// Farbe des Marmors an (x, y): wolkiger dunkler Grund, darin wellige Adern in drei Stärken, die an- und
    /// abschwellen (statt durchgehender Linien), dazu feines Funkeln.
    public static func marble(_ x: Int, _ y: Int) -> RGBA {
        let fx = Double(x), fy = Double(y)
        let cloud = smoothNoise(fx / 26, fy / 26) * 0.6 + smoothNoise(fx / 9 + 40, fy / 9) * 0.4
        let warp = 22 * (smoothNoise(fx / 40 + 7, fy / 40) - 0.5) + 9 * sin(fy * 0.05 + fx * 0.013)
        let fade = smoothNoise(fx / 30 + 90, fy / 30 + 3)
        let main = abs(sin((fx + warp) * 0.026 + fy * 0.021))
        let second = abs(sin((fx * 0.6 - warp * 1.4) * 0.05 - fy * 0.031 + 1.7))
        let fine = abs(sin((fx + warp * 2.2) * 0.11 + fy * 0.07))
        let speck = noise(x, y)
        if main < 0.04 && fade > 0.35 { return speck > 0.5 ? marbleVeinLight : marbleVein }
        if main < 0.1 && fade > 0.45 { return marbleVein.mixed(with: marbleMid, 0.5) }
        if second < 0.035 && fade > 0.5 { return marbleVein }
        if fine < 0.025 && cloud > 0.55 { return marbleMid.mixed(with: marbleVein, 0.5) }
        if speck > 0.985 { return marbleVeinLight.withAlpha(255).shaded(0.8) }
        let base = marbleBase.mixed(with: marbleMid, cloud > 0.62 ? 0.9 : cloud > 0.45 ? 0.45 : 0)
        return base
    }

    /// Fester Zufall je Pixel (0…1), damit der Boden bei jedem Zeichnen gleich aussieht.
    static func noise(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h % 10_000) / 10_000
    }

    /// Weiches Rauschen (Werte auf einem Gitter, dazwischen geglättet).
    static func smoothNoise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let tx = x - Double(x0), ty = y - Double(y0)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = noise(x0, y0), b = noise(x0 + 1, y0), c = noise(x0, y0 + 1), d = noise(x0 + 1, y0 + 1)
        return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    }

    // MARK: Wände, Galerie, Treppe

    static func drawUpperWall(_ c: inout PixelCanvas, daylight: Double) {
        // Wellblech: senkrechte Rippen.
        for y in 0..<OfficeLayout.galleryTop {
            for x in 0..<OfficeLayout.width {
                c.replace(x, y, x % 4 < 2 ? steel : steelDark)
            }
        }
        c.fill(0, 0, OfficeLayout.width, 2, steelLight)  // Träger oben
        // Drei hohe Fenster mit Sprossen.
        let night = RGBA(hex: 0x101A33), day = RGBA(hex: 0x9CC7EA)
        let glass = night.mixed(with: day, daylight)
        for wx in [42, 150, 258] {
            c.fill(wx - 1, 3, 54, 12, steelEdge)
            c.fill(wx, 4, 52, 10, glass)
            for py in 4..<14 where daylight > 0.3 { c.hline(wx, py, 52, RGBA(255, 255, 255, UInt8(10 * (14 - py)))) }
            for sx in stride(from: wx + 12, to: wx + 52, by: 13) { c.vline(sx, 4, 10, steelEdge) }
            c.hline(wx, 8, 52, steelEdge)
            if daylight < 0.5 {
                // Ein paar Sterne.
                for (dx, dy) in [(5, 6), (21, 10), (33, 5), (46, 11), (9, 12)] {
                    c.set(wx + dx, 4 + dy % 10, RGBA(255, 255, 255, UInt8(180 * (1 - daylight * 2))))
                }
            }
        }
    }

    static func drawGallery(_ c: inout PixelCanvas) {
        // Laufsteg aus Gitterrost.
        for y in OfficeLayout.galleryTop..<(OfficeLayout.galleryFront) {
            for x in 0..<OfficeLayout.width {
                let grid = x % 3 == 0 || y % 3 == 0
                c.replace(x, y, grid ? steelDark : steel)
            }
        }
        // Vorderkante (Träger) mit Nieten und Schatten darunter.
        c.fill(0, OfficeLayout.galleryFront, OfficeLayout.width, 4, steelLight)
        c.hline(0, OfficeLayout.galleryFront, OfficeLayout.width, steelEdge)
        for x in stride(from: 4, to: OfficeLayout.width, by: 10) { c.set(x, OfficeLayout.galleryFront + 2, steelEdge) }
        // Geländer: Handlauf, Mittelholm, Pfosten.
        let rail = RGBA(hex: 0x5E6573)
        c.hline(0, OfficeLayout.galleryFront - 9, OfficeLayout.width, rail)
        c.hline(0, OfficeLayout.galleryFront - 5, OfficeLayout.width, steelLight)
        for x in stride(from: 2, to: OfficeLayout.width, by: 14)
            where !(x >= OfficeLayout.stairs.x && x < OfficeLayout.stairs.maxX) {
            c.vline(x, OfficeLayout.galleryFront - 9, 9, rail)
        }
        // Auf der Galerie: Kisten, Server-Regal, Sandsack.
        drawCrate(&c, x: 30, y: 19, w: 14, h: 11)
        drawCrate(&c, x: 46, y: 22, w: 10, h: 8)
        drawCrate(&c, x: 64, y: 21, w: 12, h: 9)
        c.fill(300, 15, 14, 16, RGBA(hex: 0x15161A))
        c.frame(300, 15, 14, 16, steelEdge)
        for ry in stride(from: 17, to: 30, by: 3) { c.hline(302, ry, 10, RGBA(hex: 0x2A2D34)) }
        // Sandsack hängt an einer Kette von der Decke.
        c.vline(240, 0, 16, RGBA(hex: 0x6B7280))
        c.fill(236, 16, 9, 14, RGBA(hex: 0x8E1B24))
        c.fill(237, 17, 2, 12, RGBA(hex: 0xB0262F))
        c.hline(236, 16, 9, RGBA(hex: 0x111111))
        c.hline(236, 29, 9, RGBA(hex: 0x111111))
    }

    static func drawCrate(_ c: inout PixelCanvas, x: Int, y: Int, w: Int, h: Int) {
        c.fill(x, y, w, h, RGBA(hex: 0x5A4630))
        c.frame(x, y, w, h, RGBA(hex: 0x3A2C1E))
        c.line(x, y, x + w - 1, y + h - 1, RGBA(hex: 0x3A2C1E))
        c.hline(x + 1, y + 1, w - 2, RGBA(hex: 0x6E5640))
    }

    static func drawBrickWall(_ c: inout PixelCanvas) {
        let top = OfficeLayout.galleryFront + 4, bottom = OfficeLayout.floorTop
        for y in top..<bottom {
            let row = (y - top) / 4
            for x in 0..<OfficeLayout.width {
                let offset = row % 2 == 0 ? 0 : 5
                let mortarRow = (y - top) % 4 == 3
                let mortarCol = (x + offset) % 10 == 9
                var color: RGBA
                if mortarRow || mortarCol {
                    color = mortar
                } else {
                    let pick = noise((x + offset) / 10, row) * 3
                    color = pick < 1 ? brickA : pick < 2 ? brickB : brickC
                }
                // Unter der Galerie liegt die Wand im Schatten.
                let depth = Double(y - top) / Double(bottom - top)
                c.replace(x, y, color.shaded(0.55 + 0.45 * depth))
            }
        }
        // Stützen der Galerie (Doppel-T-Träger).
        for sx in [110, 226] {
            c.fill(sx, top, 5, bottom - top + 6, steelLight)
            c.vline(sx, top, bottom - top + 6, steelEdge)
            c.vline(sx + 4, top, bottom - top + 6, steelDark)
            c.fill(sx - 1, bottom + 4, 7, 2, steelDark)
        }
        // Sockel: Übergang zum Boden.
        c.hline(0, bottom - 1, OfficeLayout.width, RGBA(hex: 0x0E0E11))
        c.hline(0, bottom, OfficeLayout.width, RGBA(0, 0, 0, 120))
        c.hline(0, bottom + 1, OfficeLayout.width, RGBA(0, 0, 0, 60))
    }

    static func drawRollerDoor(_ c: inout PixelCanvas) {
        let r = OfficeLayout.rollerDoor
        c.fill(r.x - 2, r.y - 3, r.w + 4, 3, steelLight)  // Kasten oben
        c.fill(r.x - 2, r.y, 2, r.h, steelLight)
        c.fill(r.maxX, r.y, 2, r.h, steelLight)
        for y in r.y..<(r.maxY - 2) {
            c.hline(r.x, y, r.w, (y - r.y) % 3 == 2 ? RGBA(hex: 0x3F444E) : RGBA(hex: 0x575E6A))
        }
        // Warnstreifen unten.
        for x in r.x..<r.maxX {
            let stripe = ((x - r.x) / 3) % 2 == 0
            c.hline(x, r.maxY - 2, 1, stripe ? RGBA(hex: 0xE8B41C) : RGBA(hex: 0x1A1A1A))
            c.hline(x, r.maxY - 1, 1, stripe ? RGBA(hex: 0x1A1A1A) : RGBA(hex: 0xE8B41C))
        }
        c.fill(r.x + r.w / 2 - 4, r.maxY - 6, 8, 2, RGBA(hex: 0x2A2D34))  // Griff
        // Unauffällig wie eine Schablonen-Aufschrift: der Name des Besitzers.
        c.text("BØSSA", at: r.x + 6, r.y + 5, color: RGBA(hex: 0x6E7582))
    }

    static func drawStairs(_ c: inout PixelCanvas) {
        let s = OfficeLayout.stairs
        // Stufen: oben (hinten) dunkler als unten.
        var y = s.y + 2
        var step = 0
        while y < s.maxY {
            let light = 0.7 + 0.3 * Double(y - s.y) / Double(s.h)
            c.fill(s.x + 2, y, s.w - 4, 2, RGBA(hex: 0x5A606C).shaded(light))
            c.fill(s.x + 2, y + 2, s.w - 4, 2, RGBA(hex: 0x2A2E36).shaded(light))
            c.hline(s.x + 2, y, s.w - 4, RGBA(hex: 0x6E7583).shaded(light))
            y += 4
            step += 1
        }
        // Wangen und Handläufe.
        c.fill(s.x, s.y, 2, s.h, steelLight)
        c.fill(s.maxX - 2, s.y, 2, s.h, steelLight)
        c.vline(s.x - 1, s.y - 8, s.h + 4, RGBA(hex: 0x6B7280))
        c.vline(s.maxX, s.y - 8, s.h + 4, RGBA(hex: 0x6B7280))
        for py in stride(from: s.y - 8, to: s.maxY - 4, by: 8) {
            c.set(s.x - 1, py, steelEdge)
            c.set(s.maxX, py, steelEdge)
        }
        // Schatten am Fuß der Treppe.
        c.fill(s.x, s.maxY, s.w, 2, RGBA(0, 0, 0, 80))
    }

    static func drawNeon(_ c: inout PixelCanvas) {
        // Ein Blitz aus Neonröhre an der Ziegelwand.
        let n = OfficeLayout.neon
        let pink = RGBA(hex: 0xFF4DA6)
        let points = [(n.x + 8, n.y), (n.x + 2, n.y + 9), (n.x + 7, n.y + 9), (n.x + 3, n.y + 17), (n.x + 11, n.y + 6), (n.x + 6, n.y + 6), (n.x + 10, n.y)]
        for i in 0..<(points.count - 1) {
            c.line(points[i].0, points[i].1, points[i + 1].0, points[i + 1].1, pink)
        }
    }

    static func drawProjectionSurface(_ c: inout PixelCanvas) {
        let p = OfficeLayout.projection
        c.fill(p.x - 1, p.y - 1, p.w + 2, p.h + 2, RGBA(hex: 0x1A1A1E))
        c.fill(p.x, p.y, p.w, p.h, RGBA(hex: 0x2B2B33))
    }

    static func drawSideWalls(_ c: inout PixelCanvas) {
        let wall = RGBA(hex: 0x0D0D10)
        c.fill(0, 0, OfficeLayout.wallLeft, OfficeLayout.height, wall)
        c.fill(OfficeLayout.wallRight, 0, OfficeLayout.width - OfficeLayout.wallRight, OfficeLayout.height, wall)
        c.vline(OfficeLayout.wallLeft, OfficeLayout.floorTop, OfficeLayout.height, RGBA(0, 0, 0, 120))
        c.vline(OfficeLayout.wallRight - 1, OfficeLayout.floorTop, OfficeLayout.height, RGBA(0, 0, 0, 120))
    }

    static func drawRug(_ c: inout PixelCanvas) {
        let r = OfficeLayout.rug
        c.fill(r.x, r.y, r.w, r.h, RGBA(hex: 0x2A1418))
        c.frame(r.x + 2, r.y + 2, r.w - 4, r.h - 4, RGBA(hex: 0x6B2A2F))
        c.frame(r.x + 4, r.y + 4, r.w - 8, r.h - 8, RGBA(hex: 0x3A1A1E))
        for x in stride(from: r.x + 8, to: r.maxX - 8, by: 8) {
            c.set(x, r.y + 3, RGBA(hex: 0x8A3A3F))
            c.set(x, r.maxY - 4, RGBA(hex: 0x8A3A3F))
        }
    }

    // MARK: Möbel

    static func fridgeProp() -> OfficeProp {
        let r = OfficeLayout.fridge
        var c = PixelCanvas(width: r.w, height: r.h)
        let body = RGBA(hex: 0x1E3F8C), bodyDark = RGBA(hex: 0x142B63)
        c.fill(0, 0, r.w, r.h, body)
        c.fill(r.w - 3, 0, 3, r.h, bodyDark)
        // Kopfleiste rot mit gelbem Kreis (die Dose in Farbe angedeutet, kein Logo).
        c.fill(0, 0, r.w, 6, RGBA(hex: 0xC8102E))
        c.ellipse(r.w / 2 - 3, 1, 5, 4, RGBA(hex: 0xF2C200))
        // Glastür mit Licht und drei Regalen voller Dosen.
        c.fill(2, 8, r.w - 6, r.h - 12, RGBA(hex: 0xC9DBF5))
        for shelf in 0..<3 {
            let sy = 10 + shelf * 8
            c.hline(2, sy + 6, r.w - 6, RGBA(hex: 0x8DA4C4))
            for cx in stride(from: 3, to: r.w - 5, by: 3) {
                c.fill(cx, sy + 1, 2, 5, RGBA(hex: 0x2A55B8))
                c.set(cx, sy + 1, RGBA(hex: 0xD9DEE6))
                c.set(cx + 1, sy + 1, RGBA(hex: 0xD9DEE6))
                c.set(cx, sy + 3, RGBA(hex: 0xC8102E))
            }
        }
        c.vline(r.w - 5, 12, 10, RGBA(hex: 0xE6EEF9))  // Griff
        c.frame(0, 0, r.w, r.h, RGBA(hex: 0x0E1F47))
        return OfficeProp(name: "fridge", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    /// Getunte Sportwagen im Profil (nach rechts), tiefergelegt mit großen Felgen und Heckflügel:
    /// oben ein pinker Nissan GT-R (lange Haube, runde Rückleuchten), darunter ein limettengrüner Porsche 911
    /// (fließendes Heck, runde Scheinwerfer). Maße nach den echten Autos (≈ 19 px je Meter).
    static func carProp(gtr: Bool) -> OfficeProp {
        let r = gtr ? OfficeLayout.gtr : OfficeLayout.porsche
        var c = PixelCanvas(width: r.w, height: r.h)
        let paint = gtr ? RGBA(hex: 0xFF4FA3) : RGBA(hex: 0xA8E61D)
        let dark = gtr ? RGBA(hex: 0xBF2E7C) : RGBA(hex: 0x6E9F0F)
        let light = gtr ? RGBA(hex: 0xFFA3D2) : RGBA(hex: 0xDFFF7A)
        let glass = RGBA(hex: 0x121621), glassLight = RGBA(hex: 0x39435F)
        let carbon = RGBA(hex: 0x1A1A1E)
        let groundY = r.h - 1
        let top = Double(groundY - 26)  // Oberkante (Dach) bei etwa 26 px über dem Boden
        func p(_ x: Double, _ y: Double) -> (Double, Double) { (x, top + y) }
        // Schatten am Boden.
        c.ellipse(1, groundY - 3, r.w - 2, 5, RGBA(0, 0, 0, 120))
        let wheels: [Double]
        let body: [(Double, Double)]
        let windows: [(Double, Double)]
        let pillar: Double
        if gtr {
            wheels = [21, 75]
            body = [p(1, 22), p(0, 17), p(2, 13), p(13, 11), p(31, 3), p(49, 2), p(61, 10), p(84, 12),
                    p(91, 15), p(93, 20), p(91, 23), p(2, 23)]
            windows = [p(17, 11), p(31, 5), p(48, 4), p(57, 10.5)]
            pillar = 42
        } else {
            wheels = [23, 70]
            body = [p(2, 23), p(0, 20), p(0, 16), p(2, 13), p(6, 10), p(14, 7), p(27, 3.5), p(37, 2.5), p(45, 3.5),
                    p(54, 10), p(76, 12), p(83, 13), p(87, 16), p(88, 20), p(86, 23)]
            windows = [p(14, 10), p(27, 5.5), p(38, 4.2), p(44, 5), p(51, 10.5)]
            pillar = 40
        }
        c.polygon(body, paint)
        // Volumen: unten dunkler, Schulterlinie hell.
        for y in 0..<r.h {
            for x in 0..<r.w where c[x, y] == paint {
                let row = Double(y) - top
                if row >= 18 { c.replace(x, y, dark) } else if row >= 13 && row < 14 { c.replace(x, y, light) }
            }
        }
        c.polygon(windows, glass)
        c.line(Int(windows[1].0) + 2, Int(windows[1].1) + 1, Int(pillar) - 2, Int(windows[2].1) + 1, glassLight)
        c.vline(Int(pillar), Int(top) + 3, 8, paint)  // B-Säule
        c.vline(Int(pillar) - 1, Int(top) + 12, 6, dark)  // Türfuge
        // Tuning: Splitter vorn, Seitenschweller, Heckflügel aus Karbon.
        c.hline(r.w - 12, groundY - 3, 11, carbon)
        c.hline(Int(wheels[0]) + 8, groundY - 3, Int(wheels[1] - wheels[0]) - 16, carbon)
        // Heckflügel: Karbonblatt mit heller Kante, Endplatten in Wagenfarbe, zwei Stützen.
        let wingY = Int(top) + (gtr ? 4 : 2)
        let wingW = gtr ? 17 : 15
        c.fill(0, wingY, wingW, 2, RGBA(hex: 0x2E2E36))
        c.hline(0, wingY, wingW, RGBA(hex: 0x5A5A66))
        c.fill(0, wingY - 1, 2, 4, paint)
        c.vline(5, wingY + 2, gtr ? 7 : 8, RGBA(hex: 0x3A3A44))
        c.vline(11, wingY + 2, gtr ? 6 : 7, RGBA(hex: 0x3A3A44))
        // Neon-Unterbodenbeleuchtung (leuchtet nachts, Licht kommt aus dem Overlay der App).
        c.hline(Int(wheels[0]) + 7, groundY - 1, Int(wheels[1] - wheels[0]) - 14, light.withAlpha(200))
        if gtr {
            // Runde Rückleuchte, schmaler Scheinwerfer, Kiemen hinter dem Vorderrad.
            c.fill(1, Int(top) + 13, 2, 3, RGBA(hex: 0xFF2A2A))
            c.set(1, Int(top) + 14, RGBA(hex: 0xFFB0B0))
            c.line(r.w - 9, Int(top) + 13, r.w - 4, Int(top) + 14, RGBA(hex: 0xEAF4FF))
            for vx in [60, 62, 64] { c.vline(vx, Int(top) + 15, 3, dark.shaded(0.7)) }
        } else {
            // Runder Scheinwerfer auf dem Kotflügel, Leuchtband hinten, Lufteinlass vorn.
            c.ellipse(r.w - 11, Int(top) + 11, 5, 4, RGBA(hex: 0xEAF4FF))
            c.set(r.w - 9, Int(top) + 12, RGBA(hex: 0xFFFFFF))
            c.hline(0, Int(top) + 13, 3, RGBA(hex: 0xFF2A2A))
            c.hline(r.w - 6, Int(top) + 20, 4, carbon)
        }
        // Räder: tief im Radkasten, große Felgen mit Speichen und farbigem Bremssattel.
        let radius = 6.8
        for wx in wheels {
            let cy = Double(groundY) - radius
            c.ellipse(Int(wx - radius - 1.5), Int(cy - radius - 1.5), Int(radius * 2 + 3), Int(radius * 2 + 2), RGBA(hex: 0x0A0A0C))
            c.ellipse(Int(wx - radius), Int(cy - radius), Int(radius * 2), Int(radius * 2), RGBA(hex: 0x141416))
            let rim = gtr ? RGBA(hex: 0xB08D57) : RGBA(hex: 0xC4C9D2)
            let rimDark = gtr ? RGBA(hex: 0x6E5732) : RGBA(hex: 0x7E8590)
            c.ellipse(Int(wx - radius + 2), Int(cy - radius + 2), Int(radius * 2 - 4), Int(radius * 2 - 4), rimDark)
            let cx = Int(wx.rounded()), cyi = Int(cy.rounded())
            for k in 0..<5 {
                let a = Double(k) * 2 * Double.pi / 5 - Double.pi / 2
                c.line(cx, cyi, cx + Int((cos(a) * 4).rounded()), cyi + Int((sin(a) * 4).rounded()), rim)
            }
            c.set(cx, cyi, RGBA(hex: 0x0A0A0C))
            c.fill(cx + 2, cyi - 3, 2, 3, gtr ? RGBA(hex: 0xE02424) : RGBA(hex: 0xF2C200))
        }
        return OfficeProp(name: gtr ? "gtr" : "911", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    static func tiresProp() -> OfficeProp {
        let r = OfficeLayout.tires
        var c = PixelCanvas(width: r.w, height: r.h)
        for i in 0..<4 {
            let y = r.h - 6 - i * 4
            c.ellipse(0, y, r.w, 6, RGBA(hex: 0x141416))
            c.ellipse(1, y, r.w - 2, 4, RGBA(hex: 0x24242A))
            c.ellipse(4, y + 1, r.w - 8, 2, RGBA(hex: 0x0A0A0B))
        }
        return OfficeProp(name: "tires", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    /// Seitlich gedrehte, aneinandergestellte Tische: ein langer Block, an jeder Seite drei Plätze mit
    /// Gaming-Stuhl. Die Bildschirme stehen Rücken an Rücken in der Mitte (Inhalt zeichnet `OfficeRenderer`).
    static func deskBlockProp() -> OfficeProp {
        let block = OfficeLayout.deskBlock
        let x0 = block.x - 20, y0 = block.y - 8
        var c = PixelCanvas(width: block.w + 40, height: block.h + 18)
        let bx = block.x - x0, by = block.y - y0
        // Tischplatte (Draufsicht) mit Kante vorn.
        c.fill(bx, by, block.w, block.h, wood)
        c.frame(bx, by, block.w, block.h, woodDark)
        c.hline(bx + 1, by + 1, block.w - 2, woodLight)
        c.vline(bx + block.w / 2, by + 1, block.h - 2, woodDark)  // Fuge zwischen den Tischen
        c.fill(bx, by + block.h, block.w, 4, woodDark)
        c.fill(bx + 1, by + block.h + 4, 2, 5, black)
        c.fill(bx + block.w - 3, by + block.h + 4, 2, 5, black)
        for seat in OfficeLayout.seats {
            let left = seat.facing == .right
            let sx = seat.screen.x - x0, sy = seat.screen.y - y0
            // Bildschirm schräg von der Seite: Rahmen, Ständer, Fuß.
            let screenFace: [(Double, Double)] = left
                ? [(Double(sx), Double(sy + 1)), (Double(sx + 6), Double(sy)), (Double(sx + 6), Double(sy + 14)), (Double(sx), Double(sy + 12))]
                : [(Double(sx), Double(sy)), (Double(sx + 6), Double(sy + 1)), (Double(sx + 6), Double(sy + 12)), (Double(sx), Double(sy + 14))]
            c.polygon(screenFace, RGBA(hex: 0x0E0F12))
            c.vline(left ? sx + 6 : sx - 1, sy, 15, RGBA(hex: 0x2A2D34))
            c.fill(sx + 2, sy + 14, 2, 3, RGBA(hex: 0x3A3D44))
            c.fill(sx, sy + 17, 6, 1, RGBA(hex: 0x3A3D44))
            // Tastatur und Dose vor dem Platz.
            let kx = left ? bx + 1 : bx + block.w - 3
            c.fill(kx, sy + 15, 2, 6, RGBA(hex: 0xC9CCD3))
            c.fill(left ? bx + 3 : bx + block.w - 5, sy + 4, 2, 3, RGBA(hex: 0x2A55B8))
            // Gaming-Stuhl im Profil, Lehne außen (schaut zum Tisch).
            let chairX = left ? Int(seat.sit.x) - x0 - 7 : Int(seat.sit.x) - x0 - 2
            c.sprite(chairRows, palette: chairPalette, at: chairX, Int(seat.sit.y) - y0 - 20, flipped: !left)
        }
        return OfficeProp(name: "desks", x: x0, y: y0, canvas: c, baseline: block.maxY + 4)
    }

    /// Gaming-Stuhl im Profil, schaut nach rechts (Lehne links). K schwarz, R rot, G Gasfeder, W Rollen.
    static let chairRows = [
        ".KKK.......",
        "KRRK.......",
        "KRRK.......",
        ".KK........",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRK.......",
        "KRRKKKKKKK.",
        "KKKKKKKKKKK",
        ".KK.....KK.",
        ".....G.....",
        ".....G.....",
        "....GGG....",
        ".GGGGGGGGG.",
        ".W.......W.",
    ]
    static let chairPalette: [Character: RGBA] = [
        "K": RGBA(hex: 0x17171B), "R": RGBA(hex: 0xB0182B), "G": RGBA(hex: 0x3A3A42), "W": RGBA(hex: 0x0A0A0C),
    ]

    static func couchProp() -> OfficeProp {
        let r = OfficeLayout.couch
        var c = PixelCanvas(width: r.w, height: r.h)
        let leather = RGBA(hex: 0x2B1F1C), leatherLight = RGBA(hex: 0x3D2C27), leatherDark = RGBA(hex: 0x1A1210)
        c.fill(4, 0, r.w - 8, 9, leather)  // Lehne
        for x in stride(from: 8, to: r.w - 8, by: 6) { c.set(x, 4, leatherDark) }  // Knöpfe
        c.hline(4, 0, r.w - 8, leatherLight)
        c.fill(4, 9, r.w - 8, 8, leatherLight)  // Sitzpolster
        for x in stride(from: 4 + (r.w - 8) / 3, to: r.w - 5, by: (r.w - 8) / 3) { c.vline(x, 9, 8, leather) }
        c.fill(0, 4, 5, r.h - 6, leather)  // Armlehnen
        c.fill(r.w - 5, 4, 5, r.h - 6, leather)
        c.hline(0, 4, 5, leatherLight)
        c.hline(r.w - 5, 4, 5, leatherLight)
        c.fill(4, 17, r.w - 8, 3, leatherDark)  // Front
        c.fill(2, r.h - 2, 2, 2, black)
        c.fill(r.w - 4, r.h - 2, 2, 2, black)
        // Kissen in den Farben von Claude und Codex.
        c.fill(6, 4, 6, 6, RGBA(hex: 0xE0764A))
        c.fill(r.w - 12, 4, 6, 6, RGBA(hex: 0x6E86F5))
        return OfficeProp(name: "couch", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    static func tableProp() -> OfficeProp {
        let r = OfficeLayout.table
        var c = PixelCanvas(width: r.w, height: r.h)
        c.fill(0, 0, r.w, r.h - 3, RGBA(hex: 0x18181D))
        c.frame(0, 0, r.w, r.h - 3, RGBA(hex: 0x30303A))
        c.hline(1, 1, r.w - 2, RGBA(hex: 0x3C3C48))
        c.fill(1, r.h - 3, 2, 3, black)
        c.fill(r.w - 3, r.h - 3, 2, 3, black)
        for (cx, cy) in [(6, 3), (10, 4), (24, 3)] {  // Dosen
            c.fill(cx, cy, 2, 4, RGBA(hex: 0x2A55B8))
            c.hline(cx, cy, 2, RGBA(hex: 0xD9DEE6))
            c.set(cx, cy + 2, RGBA(hex: 0xC8102E))
        }
        c.fill(15, 4, 6, 3, RGBA(hex: 0xE8E8EC))  // Controller
        c.set(16, 5, RGBA(hex: 0x2A2A30))
        c.set(19, 5, RGBA(hex: 0x2A2A30))
        return OfficeProp(name: "table", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    static func floorLampProp() -> OfficeProp {
        let r = OfficeLayout.floorLamp
        var c = PixelCanvas(width: r.w, height: r.h)
        let metal = RGBA(hex: 0x2E3139)
        c.fill(14, r.h - 3, 8, 3, metal)  // Fuß
        c.vline(18, 10, r.h - 12, metal)  // Stange
        c.line(18, 10, 6, 5, metal)  // Bogen zur Couch
        c.fill(1, 5, 10, 4, RGBA(hex: 0x1A1A1E))  // Schirm
        c.fill(2, 9, 8, 1, RGBA(hex: 0xFFE2A8))  // Licht
        return OfficeProp(name: "lamp", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    /// Breites Bett an der rechten Wand, Kopfende rechts; darüber hängt der Beamer.
    static func bedProp() -> OfficeProp {
        let r = OfficeLayout.bed
        var c = PixelCanvas(width: r.w, height: r.h)
        c.fill(0, 0, r.w - 6, r.h - 4, RGBA(hex: 0x2A2A30))  // Rahmen
        c.fill(r.w - 6, 0, 6, r.h - 2, RGBA(hex: 0x1C1C22))  // Kopfteil an der Wand
        for y in stride(from: 2, to: r.h - 4, by: 5) { c.hline(r.w - 5, y, 4, RGBA(hex: 0x2A2A32)) }
        c.fill(2, 2, r.w - 9, r.h - 8, RGBA(hex: 0xE6E6EA))  // Laken
        c.fill(2, 2, r.w - 22, r.h - 8, RGBA(hex: 0x30323C))  // Bettdecke
        c.hline(2, 2, r.w - 22, RGBA(hex: 0x40434F))
        c.vline(r.w - 21, 2, r.h - 8, RGBA(hex: 0x40434F))
        for y in stride(from: 6, to: r.h - 6, by: 6) { c.hline(4, y, r.w - 26, RGBA(hex: 0x2A2C35)) }
        c.fill(r.w - 18, 4, 10, 14, RGBA(hex: 0xF4F4F7))  // Kissen
        c.fill(r.w - 18, 22, 10, 14, RGBA(hex: 0xF4F4F7))
        c.frame(r.w - 18, 4, 10, 14, RGBA(hex: 0xC9C9D1))
        c.frame(r.w - 18, 22, 10, 14, RGBA(hex: 0xC9C9D1))
        c.fill(0, r.h - 4, r.w - 6, 2, RGBA(hex: 0x1E1E24))  // Front
        return OfficeProp(name: "bed", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    static func projectorProp() -> OfficeProp {
        let r = OfficeLayout.projector
        var c = PixelCanvas(width: r.w, height: r.h)
        c.vline(r.w / 2, 0, 4, RGBA(hex: 0x6B7280))  // Halterung an der Decke
        c.fill(1, 4, r.w - 2, 5, RGBA(hex: 0xE4E6EB))
        c.hline(1, 8, r.w - 2, RGBA(hex: 0xA9ADB6))
        c.fill(3, 4, 3, 2, RGBA(hex: 0x1A1A1E))  // Linse (zeigt zur Rückwand)
        c.set(r.w - 3, 6, RGBA(hex: 0x44E07A))
        return OfficeProp(name: "projector", x: r.x, y: r.y, canvas: c, baseline: OfficeLayout.bed.maxY + 1)
    }

    /// Billardtisch (Draufsicht): Holzbande, grünes Tuch, sechs Taschen, ein paar Kugeln und ein Queue.
    static func poolTableProp() -> OfficeProp {
        let r = OfficeLayout.poolTable
        var c = PixelCanvas(width: r.w, height: r.h)
        c.fill(0, 0, r.w, r.h - 4, woodDark)
        c.hline(0, 0, r.w, woodLight)
        c.fill(3, 3, r.w - 6, r.h - 10, RGBA(hex: 0x1E6B45))
        c.frame(3, 3, r.w - 6, r.h - 10, RGBA(hex: 0x17563A))
        for (px, py) in [(2, 2), (r.w / 2 - 1, 1), (r.w - 4, 2), (2, r.h - 8), (r.w / 2 - 1, r.h - 7), (r.w - 4, r.h - 8)] {
            c.fill(px, py, 2, 2, RGBA(hex: 0x050505))
        }
        let balls: [(Int, Int, UInt32)] = [(14, 12, 0xF5F5F0), (38, 10, 0xE8B41C), (41, 14, 0xC8102E), (44, 11, 0x1E4FB8),
                                           (40, 18, 0x111111), (30, 20, 0x7A2BA8), (22, 8, 0x2E8B3A)]
        for (bx, by, color) in balls {
            c.fill(bx, by, 2, 2, RGBA(hex: color))
        }
        c.line(6, 22, 13, 13, RGBA(hex: 0xC9A26B))  // Queue
        c.fill(0, r.h - 4, r.w, 2, RGBA(hex: 0x2B1A12))
        c.fill(2, r.h - 2, 3, 2, black)
        c.fill(r.w - 5, r.h - 2, 3, 2, black)
        return OfficeProp(name: "pool", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }

    static func plantProp() -> OfficeProp {
        let r = OfficeLayout.plant
        var c = PixelCanvas(width: r.w, height: r.h)
        c.fill(4, r.h - 7, 8, 7, RGBA(hex: 0x2A2D34))
        c.hline(4, r.h - 7, 8, RGBA(hex: 0x3D424B))
        let leaf = RGBA(hex: 0x2F6B3A), leafLight = RGBA(hex: 0x3F8A4C)
        for (lx, ly, w, h) in [(2, 6, 6, 5), (8, 3, 6, 6), (5, 0, 5, 5), (0, 11, 6, 5), (9, 10, 7, 6), (5, 8, 6, 6)] {
            c.ellipse(lx, ly, w, h, leaf)
            c.set(lx + w / 2, ly + 1, leafLight)
        }
        c.vline(8, 12, r.h - 19, RGBA(hex: 0x24502C))
        return OfficeProp(name: "plant", x: r.x, y: r.y, canvas: c, baseline: r.maxY)
    }
}
