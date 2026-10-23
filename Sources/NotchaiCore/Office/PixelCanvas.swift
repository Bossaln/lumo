import Foundation

/// Farbe eines Pixels mit Kanälen 0…255.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Aus `0xRRGGBB`.
    public init(hex: UInt32, alpha: UInt8 = 255) {
        self.init(UInt8(hex >> 16 & 0xFF), UInt8(hex >> 8 & 0xFF), UInt8(hex & 0xFF), alpha)
    }

    public static let clear = RGBA(0, 0, 0, 0)

    /// Heller (> 1) oder dunkler (< 1), Alpha bleibt.
    public func shaded(_ factor: Double) -> RGBA {
        func c(_ v: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(v) * factor).rounded()))) }
        return RGBA(c(r), c(g), c(b), a)
    }

    /// Mischung mit `other`: 0 = diese Farbe, 1 = `other`.
    public func mixed(with other: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGBA(m(r, other.r), m(g, other.g), m(b, other.b), m(a, other.a))
    }

    public func withAlpha(_ alpha: UInt8) -> RGBA { RGBA(r, g, b, alpha) }

    /// `self` über `below` gelegt (Quelle über Ziel).
    func over(_ below: RGBA) -> RGBA {
        if a == 255 || below.a == 0 { return a == 0 ? below : self }
        if a == 0 { return below }
        let sa = Double(a) / 255, da = Double(below.a) / 255
        let outA = sa + da * (1 - sa)
        func ch(_ s: UInt8, _ d: UInt8) -> UInt8 {
            UInt8(min(255, ((Double(s) * sa + Double(d) * da * (1 - sa)) / outA).rounded()))
        }
        return RGBA(ch(r, below.r), ch(g, below.g), ch(b, below.b), UInt8((outA * 255).rounded()))
    }
}

/// Puffer für Pixelgrafik, Zeile für Zeile von oben links. Alles im Büro wird hier hineingezeichnet
/// (Konzept: keine fertigen Grafiken), unter Linux testbar und als Vorschaubild ausgebbar.
public struct PixelCanvas: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [RGBA]

    public init(width: Int, height: Int, fill: RGBA = .clear) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill, count: width * height)
    }

    /// Außerhalb des Puffers durchsichtig.
    public subscript(x: Int, y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        return pixels[y * width + x]
    }

    /// Setzt ein Pixel; halb durchsichtige Farben mischen sich mit dem, was darunter liegt.
    public mutating func set(_ x: Int, _ y: Int, _ color: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height, color.a > 0 else { return }
        let i = y * width + x
        pixels[i] = color.over(pixels[i])
    }

    /// Ersetzt ein Pixel ohne Mischen.
    public mutating func replace(_ x: Int, _ y: Int, _ color: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = color
    }

    public mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        let x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { set(xx, yy, color) }
        }
    }

    public mutating func hline(_ x: Int, _ y: Int, _ w: Int, _ color: RGBA) { fill(x, y, w, 1, color) }
    public mutating func vline(_ x: Int, _ y: Int, _ h: Int, _ color: RGBA) { fill(x, y, 1, h, color) }

    /// Umriss eines Rechtecks.
    public mutating func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        hline(x, y, w, color)
        hline(x, y + h - 1, w, color)
        vline(x, y, h, color)
        vline(x + w - 1, y, h, color)
    }

    /// Linie nach Bresenham.
    public mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: RGBA) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            set(x, y, color)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// Ellipse (gefüllt) im Rechteck.
    public mutating func ellipse(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        let rx = Double(w) / 2, ry = Double(h) / 2
        let cx = Double(x) + rx, cy = Double(y) + ry
        for yy in y..<(y + h) {
            for xx in x..<(x + w) {
                let nx = (Double(xx) + 0.5 - cx) / rx, ny = (Double(yy) + 0.5 - cy) / ry
                if nx * nx + ny * ny <= 1 { set(xx, yy, color) }
            }
        }
    }

    /// Gefülltes Vieleck (Pixelmitte im Vieleck, gerade-ungerade-Regel).
    public mutating func polygon(_ points: [(Double, Double)], _ color: RGBA) {
        guard points.count >= 3 else { return }
        let minX = Int(points.map(\.0).min()!.rounded(.down)), maxX = Int(points.map(\.0).max()!.rounded(.up))
        let minY = Int(points.map(\.1).min()!.rounded(.down)), maxY = Int(points.map(\.1).max()!.rounded(.up))
        for y in stride(from: max(0, minY), through: min(height - 1, maxY), by: 1) {
            let py = Double(y) + 0.5
            var crossings: [Double] = []
            for i in points.indices {
                let (x0, y0) = points[i], (x1, y1) = points[(i + 1) % points.count]
                if (y0 <= py && y1 > py) || (y1 <= py && y0 > py) {
                    crossings.append(x0 + (py - y0) / (y1 - y0) * (x1 - x0))
                }
            }
            crossings.sort()
            var i = 0
            while i + 1 < crossings.count {
                let from = max(minX, max(0, Int((crossings[i] - 0.5).rounded(.up))))
                let to = min(maxX, min(width - 1, Int((crossings[i + 1] - 0.5).rounded(.down))))
                for x in stride(from: from, through: to, by: 1) { set(x, y, color) }
                i += 2
            }
        }
    }

    /// Sprite aus Textzeilen: Jedes Zeichen ist ein Pixel aus `palette`, unbekannte Zeichen (z. B. „.“)
    /// bleiben durchsichtig. `flipped` spiegelt waagrecht (Figur schaut in die andere Richtung).
    public mutating func sprite(_ rows: [String], palette: [Character: RGBA], at x: Int, _ y: Int, flipped: Bool = false) {
        for (dy, row) in rows.enumerated() {
            let chars = Array(row)
            for (dx, ch) in chars.enumerated() {
                guard let color = palette[ch] else { continue }
                set(flipped ? x + chars.count - 1 - dx : x + dx, y + dy, color)
            }
        }
    }

    /// Text in der 3×5-Schrift; gibt die Breite zurück.
    @discardableResult
    public mutating func text(_ string: String, at x: Int, _ y: Int, color: RGBA) -> Int {
        var cx = x
        for ch in string.uppercased() {
            if let glyph = PixelFont.glyph(ch) {
                for (dy, row) in glyph.enumerated() {
                    for (dx, bit) in row.enumerated() where bit == "#" { set(cx + dx, y + dy, color) }
                }
            }
            cx += PixelFont.width + 1
        }
        return max(0, cx - x - 1)
    }

    /// Legt einen anderen Puffer darüber.
    public mutating func draw(_ other: PixelCanvas, at x: Int, _ y: Int) {
        for oy in 0..<other.height {
            for ox in 0..<other.width { set(x + ox, y + oy, other.pixels[oy * other.width + ox]) }
        }
    }

    /// Bytes in der Reihenfolge R, G, B, A (für `CGImage` und Vorschaubilder).
    public var rgbaBytes: [UInt8] {
        [UInt8](unsafeUninitializedCapacity: pixels.count * 4) { buffer, count in
            var i = 0
            for p in pixels {
                buffer[i] = p.r
                buffer[i + 1] = p.g
                buffer[i + 2] = p.b
                buffer[i + 3] = p.a
                i += 4
            }
            count = i
        }
    }
}
