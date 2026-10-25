import Foundation

/// Die Begrüßungsszene nach `brew install`: ein MacBook mit Notch, das Leuchten der Ersteinrichtung, das in die
/// Notch zieht, ein Signal von Claude Code, das erlaubt wird, und Musik neben der Kamera. Reine Berechnung auf
/// einer Zeichenfläche, damit sich jedes Bild ohne Terminal prüfen lässt.
struct WelcomeScene {
    // 256-Farben des Terminals.
    static let orange = 208, orangeBright = 214, orangeDark = 130, orangeDim = 94
    static let screen = 234, lid = 245, body = 250, notch = 16, white = 255, gray = 245, dim = 240
    static let pink = 205, button = 238

    struct Cell: Equatable {
        var symbol: Character = " "
        var fg: Int?
        var bg: Int?
        var bold = false
    }

    /// Zeichenfläche mit Zellen; Zeichnen außerhalb wird ignoriert.
    struct Canvas {
        let width: Int
        let height: Int
        var cells: [[Cell]]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            cells = Array(repeating: Array(repeating: Cell(), count: width), count: height)
        }

        mutating func put(_ x: Int, _ y: Int, _ symbol: Character, fg: Int? = nil, bg: Int? = nil, bold: Bool = false) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let keepBackground = cells[y][x].bg
            cells[y][x] = Cell(symbol: symbol, fg: fg, bg: bg ?? keepBackground, bold: bold)
        }

        mutating func text(_ x: Int, _ y: Int, _ string: String, fg: Int? = nil, bg: Int? = nil, bold: Bool = false) {
            for (offset, character) in string.enumerated() { put(x + offset, y, character, fg: fg, bg: bg, bold: bold) }
        }

        mutating func fill(x: Int, y: Int, width: Int, height: Int, _ symbol: Character = " ", fg: Int? = nil, bg: Int? = nil) {
            for row in y..<(y + height) { for column in x..<(x + width) { put(column, row, symbol, fg: fg, bg: bg) } }
        }

        func symbol(_ x: Int, _ y: Int) -> Character {
            guard x >= 0, x < width, y >= 0, y < height else { return " " }
            return cells[y][x].symbol
        }

        /// Zeilen mit Farbcodes; gleiche Farben werden zu einem Lauf, jede Zeile endet gelöscht bis zum Rand.
        func render() -> String {
            cells.map { row in
                var trimmed = row
                while let last = trimmed.last, last == Cell() { trimmed.removeLast() }
                var out = ""
                var current: (Int?, Int?, Bool) = (nil, nil, false)
                for cell in trimmed {
                    let wanted = (cell.fg, cell.bg, cell.bold)
                    if wanted != current {
                        var codes = ["0"]
                        if let fg = cell.fg { codes.append("38;5;\(fg)") }
                        if let bg = cell.bg { codes.append("48;5;\(bg)") }
                        if cell.bold { codes.append("1") }
                        out += "\u{1B}[\(codes.joined(separator: ";"))m"
                        current = wanted
                    }
                    out.append(cell.symbol)
                }
                return out + "\u{1B}[0m\u{1B}[K"
            }.joined(separator: "\n")
        }
    }

    struct Frame: Equatable {
        var text: String
        var pause: Double
    }

    // MARK: - Geometrie

    static let height = 15
    let width: Int
    let lidX: Int, lidWidth: Int
    let screenX: Int, screenWidth: Int
    static let screenTop = 1, screenRows = 7, lidBottom = 8, baseTop = 9, baseBottom = 10
    static let textRow = 12, tipRow = 13, supportRow = 14
    static let notchWidth = 9
    let notchX: Int
    var notchCenter: Double { Double(notchX) + Double(Self.notchWidth) / 2 }

    init(columns: Int) {
        width = min(max(columns - 1, 49), 120)
        lidWidth = min(width - 2, 64)
        lidX = (width - lidWidth) / 2
        screenX = lidX + 2
        screenWidth = lidWidth - 4
        notchX = screenX + (screenWidth - Self.notchWidth) / 2
    }

    // MARK: - Zustand eines Bildes

    struct Island: Equatable {
        var width: Int
        var height: Int
        var lines: [[(String, Int?, Int?)]] = []
        var glow: Int = WelcomeScene.orange
        static func == (lhs: Island, rhs: Island) -> Bool { lhs.width == rhs.width && lhs.height == rhs.height }
    }

    struct State {
        /// Wie viele Zeilen des MacBooks schon stehen (Aufbau).
        var laptopRows = 11
        /// Radius des zusammenziehenden Lichtrings, `nil` ohne Ring.
        var ring: Double?
        /// Leuchten der Notch 0…1.
        var glow = 0.0
        var island: Island?
        /// Bild der Musikanzeige neben der Kamera.
        var music: Int?
        /// Lautstärke der Balken 0…1 (zum Ausblenden).
        var musicLevel = 1.0
        var showText = false
    }

    // MARK: - Zeichnen

    func draw(_ state: State) -> Canvas {
        var c = Canvas(width: width, height: Self.height)
        drawLaptop(&c, rows: state.laptopRows)
        if let ring = state.ring { drawRing(&c, radius: ring) }
        if let island = state.island { drawIsland(&c, island) } else { drawNotch(&c, glow: state.glow) }
        if let music = state.music { drawMusic(&c, frame: music, level: state.musicLevel) }
        if state.showText { drawText(&c) }
        return c
    }

    private func drawLaptop(_ c: inout Canvas, rows: Int) {
        let right = lidX + lidWidth - 1
        for row in 0..<min(rows, 11) {
            switch row {
            case 0:
                c.put(lidX, 0, "╭", fg: Self.lid); c.put(right, 0, "╮", fg: Self.lid)
                for x in (lidX + 1)..<right { c.put(x, 0, "─", fg: Self.lid) }
            case Self.lidBottom:
                c.put(lidX, row, "╰", fg: Self.lid); c.put(right, row, "╯", fg: Self.lid)
                for x in (lidX + 1)..<right { c.put(x, row, "─", fg: Self.lid) }
            case Self.baseTop:
                let left = max(lidX - 3, 0), end = min(right + 3, width - 1)
                c.put(left, row, "╭", fg: Self.body); c.put(end, row, "╮", fg: Self.body)
                for x in (left + 1)..<end { c.put(x, row, "─", fg: Self.body) }
            case Self.baseBottom:
                let left = max(lidX - 3, 0), end = min(right + 3, width - 1)
                c.put(left, row, "╰", fg: Self.body); c.put(end, row, "╯", fg: Self.body)
                let pad = Int(notchCenter.rounded())
                for x in (left + 1)..<end { c.put(x, row, abs(x - pad) <= 4 ? "╌" : "─", fg: Self.body) }
            default:
                c.put(lidX, row, "│", fg: Self.lid); c.put(right, row, "│", fg: Self.lid)
                c.fill(x: screenX, y: row, width: screenWidth, height: 1, bg: Self.screen)
            }
        }
    }

    /// Abstand einer Bildschirmzelle zur Notch; Zellen sind etwa doppelt so hoch wie breit.
    private func distance(_ x: Int, _ y: Int) -> Double {
        let dx = (Double(x) + 0.5 - notchCenter) / 2, dy = Double(y - Self.screenTop)
        return (dx * dx + dy * dy).squareRoot()
    }

    var maxDistance: Double {
        max(distance(screenX, Self.screenTop + Self.screenRows - 1), distance(screenX + screenWidth - 1, Self.screenTop + Self.screenRows - 1))
    }

    /// Ein Lichtring, der vom Bildschirmrand zur Notch zusammenzieht; der Rahmen leuchtet mit, solange er außen ist.
    private func drawRing(_ c: inout Canvas, radius: Double) {
        let edgeLight = radius > maxDistance * 0.75
        for y in Self.screenTop..<(Self.screenTop + Self.screenRows) {
            for x in screenX..<(screenX + screenWidth) {
                let d = abs(distance(x, y) - radius)
                guard d < 1.6 else { continue }
                let symbol: Character = d < 0.6 ? "▒" : "░"
                c.put(x, y, symbol, fg: d < 0.6 ? Self.orange : Self.orangeDark, bg: Self.screen)
            }
        }
        if edgeLight {
            for y in 0...Self.lidBottom {
                for x in lidX..<(lidX + lidWidth) where c.symbol(x, y) != " " && c.cells[y][x].bg == nil {
                    c.cells[y][x].fg = Self.orange
                }
            }
        }
    }

    private func glowColor(_ glow: Double) -> Int? {
        switch glow {
        case ..<0.05: nil
        case ..<0.35: Self.orangeDim
        case ..<0.7: Self.orangeDark
        case ..<0.9: Self.orange
        default: Self.orangeBright
        }
    }

    /// Die schwarze Notch oben in der Bildschirmmitte, darunter ihr Leuchten.
    private func drawNotch(_ c: inout Canvas, glow: Double) {
        let y = Self.screenTop
        c.fill(x: notchX, y: y, width: Self.notchWidth, height: 1, bg: Self.notch)
        guard let color = glowColor(glow) else { return }
        c.put(notchX - 1, y, "▐", fg: color, bg: Self.screen)
        c.put(notchX + Self.notchWidth, y, "▌", fg: color, bg: Self.screen)
        for x in (notchX - 1)...(notchX + Self.notchWidth) { c.put(x, y + 1, "▀", fg: color, bg: Self.screen) }
        if glow > 0.7 {
            for x in (notchX - 3)...(notchX + Self.notchWidth + 2) where c.symbol(x, y + 1) == " " {
                c.put(x, y + 1, "▔", fg: Self.orangeDim, bg: Self.screen)
            }
        }
    }

    /// Die aufgeklappte Notch (Insel) mit ihren Zeilen; die untere Kante leuchtet in der Agentenfarbe.
    private func drawIsland(_ c: inout Canvas, _ island: Island) {
        let x = Int((notchCenter - Double(island.width) / 2).rounded())
        let y = Self.screenTop
        c.fill(x: x, y: y, width: island.width, height: island.height, bg: Self.notch)
        for (row, parts) in island.lines.enumerated() where row < island.height {
            var column = x + 2
            for (text, fg, bg) in parts {
                c.text(column, y + row, text, fg: fg ?? Self.white, bg: bg ?? Self.notch, bold: bg != nil)
                column += text.count
            }
        }
        c.put(x - 1, y, "▐", fg: island.glow, bg: Self.screen)
        c.put(x + island.width, y, "▌", fg: island.glow, bg: Self.screen)
        for x in (x - 1)...(x + island.width) { c.put(x, y + island.height, "▀", fg: island.glow, bg: Self.screen) }
    }

    /// Musik neben der Kamera: links Titel, rechts Balken, die zur Musik tanzen.
    private func drawMusic(_ c: inout Canvas, frame: Int, level volume: Double) {
        let y = Self.screenTop
        let title = "♪ One More Time"
        c.text(notchX - 2 - title.count, y, title, fg: Self.body, bg: Self.screen)
        let bars: [Character] = Array("▁▂▃▄▅▆▇█")
        for i in 0..<7 {
            let level = volume * (sin(Double(frame) * 0.9 + Double(i) * 1.3) + 1) / 2 * (0.6 + 0.4 * sin(Double(i) * 0.7 + Double(frame) * 0.3))
            let index = min(max(Int((level * Double(bars.count - 1)).rounded()), 0), bars.count - 1)
            c.put(notchX + Self.notchWidth + 2 + i, y, bars[index], fg: Self.orangeBright, bg: Self.screen)
        }
    }

    private func drawText(_ c: inout Canvas) {
        let done = InstallGreeting.doneText, tip = InstallGreeting.tipText, support = InstallGreeting.supportText
        c.text(max((width - done.count) / 2, 0), Self.textRow, done, fg: Self.pink, bold: true)
        c.text(max((width - tip.count) / 2, 0), Self.tipRow, tip, fg: Self.gray)
        c.text(max((width - Self.displayWidth(support)) / 2, 0), Self.supportRow, support, fg: Self.gray)
    }

    /// Spalten im Terminal: ein Emoji (🍺) belegt zwei.
    static func displayWidth(_ string: String) -> Int {
        string.reduce(0) { $0 + ($1.unicodeScalars.first?.properties.isEmojiPresentation == true ? 2 : 1) }
    }

    // MARK: - Ablauf

    /// Alle Bilder der Szene, nur die Zeichenfläche (ohne Cursor-Steuerung).
    func frames() -> [Frame] {
        var frames: [Frame] = []
        var state = State(laptopRows: 0)
        func add(_ pause: Double) { frames.append(Frame(text: draw(state).render(), pause: pause)) }

        // 1. Das MacBook baut sich Zeile für Zeile auf.
        for rows in 1...11 { state.laptopRows = rows; add(0.045) }
        add(0.25)

        // 2. Der Bildschirmrand leuchtet auf, das Licht zieht sich in die Notch zusammen (wie beim ersten Start).
        let steps = 26
        for step in 0..<steps {
            let t = Double(step) / Double(steps - 1)
            state.ring = maxDistance * (1 - t * t)
            state.glow = t > 0.8 ? (t - 0.8) * 5 : 0
            add(0.04)
        }
        state.ring = nil
        for pulse in 0..<8 { state.glow = 0.6 + 0.4 * sin(Double(pulse) * 0.8); add(0.06) }

        // 3. Claude Code fragt: Die Notch klappt auf, das Signal wird erlaubt, dann ist es fertig.
        let header: [(String, Int?, Int?)] = [("● ", Self.orange, nil), ("Claude Code", nil, nil), ("  ·  my-app", Self.gray, nil)]
        let ask: [(String, Int?, Int?)] = [(L("Möchte ausführen:"), Self.gray, nil), ("  npm test", nil, nil)]
        let deny = " \(L("Ablehnen")) ", allow = " \(L("Erlauben")) "
        let fullWidth = max(header.map(\.0).joined().count, ask.map(\.0).joined().count, deny.count + allow.count + 3) + 4
        let buttonPad = String(repeating: " ", count: max(fullWidth - 4 - deny.count - allow.count - 3, 0))
        func buttons(allowBg: Int, allowFg: Int) -> [(String, Int?, Int?)] {
            [(buttonPad, nil, nil), (deny, Self.white, Self.button), ("   ", nil, nil), (allow, allowFg, allowBg)]
        }
        for factor in [0.3, 0.72, 1.08, 0.97, 1.0] {
            let w = Int((Double(fullWidth) * factor).rounded())
            state.island = Island(width: max(w, Self.notchWidth), height: factor < 0.5 ? 2 : 3)
            add(0.05)
        }
        state.island = Island(width: fullWidth, height: 3, lines: [header, ask, buttons(allowBg: Self.orange, allowFg: Self.notch)])
        add(0.9)
        state.island?.lines[2] = buttons(allowBg: Self.white, allowFg: Self.notch); add(0.12)
        state.island?.lines[2] = buttons(allowBg: Self.orange, allowFg: Self.notch); add(0.12)
        state.island = Island(width: fullWidth, height: 2,
                              lines: [header, [("✓ \(L("Fertig"))", Self.orange, nil), ("  ·  npm test", Self.gray, nil)]])
        add(0.8)
        for factor in [0.6, 0.3] {
            state.island = Island(width: max(Int((Double(fullWidth) * factor).rounded()), Self.notchWidth), height: factor > 0.5 ? 2 : 1)
            add(0.05)
        }
        state.island = nil
        state.glow = 0.5

        // 4. Musik läuft: Titel links, Balken rechts neben der Kamera; die Notch atmet im Takt.
        for frame in 0..<28 { state.music = frame; state.glow = 0.4 + 0.2 * sin(Double(frame) * 0.5); add(0.08) }
        // Die Balken werden leiser, bis nur der Titel bleibt.
        for step in 1...6 { state.music = 28 + step; state.musicLevel = 1 - Double(step) / 6; add(0.06) }

        // 5. Der Satz. Das letzte Bild bleibt stehen.
        state.glow = 0.5
        state.showText = true
        add(0)
        return frames
    }
}
