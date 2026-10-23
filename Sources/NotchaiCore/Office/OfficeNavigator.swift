import Foundation

/// Wegfindung in der Halle: A* auf einem groben Raster (4 px), danach geglättet (gerade Strecken, wo frei).
/// Ziele in Möbeln (Couchplatz, Bett) erreicht die Figur über die nächste freie Stelle.
public struct OfficeNavigator: Sendable {
    public static let cell = 4

    let cols: Int
    let rows: Int
    let free: [Bool]

    public init() {
        cols = OfficeLayout.width / Self.cell
        rows = OfficeLayout.height / Self.cell
        var free = [Bool](repeating: false, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let x = Double(c * Self.cell) + Double(Self.cell) / 2, y = Double(r * Self.cell) + Double(Self.cell) / 2
                free[r * cols + c] = OfficeLayout.isWalkable(x, y)
            }
        }
        self.free = free
    }

    func isFree(_ c: Int, _ r: Int) -> Bool {
        c >= 0 && r >= 0 && c < cols && r < rows && free[r * cols + c]
    }

    func cellOf(_ p: PixelPoint) -> (Int, Int) {
        (min(cols - 1, max(0, Int(p.x) / Self.cell)), min(rows - 1, max(0, Int(p.y) / Self.cell)))
    }

    func center(_ c: Int, _ r: Int) -> PixelPoint {
        PixelPoint(Double(c * Self.cell) + Double(Self.cell) / 2, Double(r * Self.cell) + Double(Self.cell) / 2)
    }

    /// Nächste freie Zelle (für Start- oder Zielpunkte in Möbeln).
    func nearestFree(_ p: PixelPoint) -> (Int, Int)? {
        let (c0, r0) = cellOf(p)
        if isFree(c0, r0) { return (c0, r0) }
        for radius in 1..<20 {
            var best: ((Int, Int), Double)?
            for dr in -radius...radius {
                for dc in -radius...radius where max(abs(dc), abs(dr)) == radius && isFree(c0 + dc, r0 + dr) {
                    let d = center(c0 + dc, r0 + dr).distance(to: p)
                    if best == nil || d < best!.1 { best = ((c0 + dc, r0 + dr), d) }
                }
            }
            if let best { return best.0 }
        }
        return nil
    }

    /// Wegpunkte von `from` nach `to` (der letzte ist genau `to`); leer, wenn es keinen Weg gibt.
    public func path(from: PixelPoint, to: PixelPoint) -> [PixelPoint] {
        guard let start = nearestFree(from), let goal = nearestFree(to) else { return [] }
        if start == goal { return [to] }
        let count = cols * rows
        var g = [Double](repeating: .infinity, count: count)
        var parent = [Int](repeating: -1, count: count)
        var closed = [Bool](repeating: false, count: count)
        var open: [(f: Double, index: Int)] = []
        let startIndex = start.1 * cols + start.0, goalIndex = goal.1 * cols + goal.0
        g[startIndex] = 0
        open.append((0, startIndex))
        func h(_ i: Int) -> Double {
            let dc = Double(abs(i % cols - goal.0)), dr = Double(abs(i / cols - goal.1))
            return max(dc, dr) + 0.414 * min(dc, dr)
        }
        while !open.isEmpty {
            // Kleine Offene Liste: lineare Suche reicht bei ~5600 Zellen.
            var best = 0
            for i in open.indices where open[i].f < open[best].f { best = i }
            let current = open.remove(at: best).index
            if current == goalIndex { break }
            if closed[current] { continue }
            closed[current] = true
            let c = current % cols, r = current / cols
            for dr in -1...1 {
                for dc in -1...1 where !(dc == 0 && dr == 0) {
                    let nc = c + dc, nr = r + dr
                    guard isFree(nc, nr) else { continue }
                    // Keine Ecken abschneiden.
                    if dc != 0 && dr != 0 && (!isFree(c + dc, r) || !isFree(c, r + dr)) { continue }
                    let ni = nr * cols + nc
                    let cost = g[current] + (dc != 0 && dr != 0 ? 1.414 : 1)
                    if cost < g[ni] {
                        g[ni] = cost
                        parent[ni] = current
                        open.append((cost + h(ni), ni))
                    }
                }
            }
        }
        guard parent[goalIndex] != -1 || goalIndex == startIndex else { return [] }
        var cells: [Int] = []
        var i = goalIndex
        while i != -1 && i != startIndex {
            cells.append(i)
            i = parent[i]
        }
        let points = cells.reversed().map { center($0 % cols, $0 / cols) }
        return smooth(from: from, points) + [to]
    }

    /// Lässt Zwischenpunkte weg, solange die gerade Strecke frei ist.
    func smooth(from: PixelPoint, _ points: [PixelPoint]) -> [PixelPoint] {
        guard points.count > 1 else { return points }
        var result: [PixelPoint] = []
        var anchor = from
        var i = 0
        while i < points.count {
            var j = points.count - 1
            while j > i && !lineIsFree(anchor, points[j]) { j -= 1 }
            result.append(points[j])
            anchor = points[j]
            i = j + 1
        }
        return result
    }

    func lineIsFree(_ a: PixelPoint, _ b: PixelPoint) -> Bool {
        let steps = max(1, Int(a.distance(to: b) / 2))
        for k in 0...steps {
            let t = Double(k) / Double(steps)
            let (c, r) = cellOf(PixelPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
            if !isFree(c, r) { return false }
        }
        return true
    }
}
