/// Begrüßung nach `brew install` und `brew upgrade`: Ein pinker GT-R lässt den Motor laufen und fährt los
/// („notchai ist installiert – los geht's!“). Das Programm `notchai-welcome` schreibt die Bilder ins Terminal;
/// hier entstehen sie, damit sie sich ohne Terminal prüfen lassen.
public enum InstallGreeting {
    /// In der Sprache des Terminals (`notchai-welcome` setzt `Localization.language`).
    public static var doneText: String { L("notchai ist installiert – los geht's!") }

    static let car = [
        "              ___________________",
        "   _ ________/  /_______|_____\\  \\_________",
        "  |_|o  ___                         ___    \\",
        "  |___ /   \\_______________________/   \\___=|>",
        "       \\___/                       \\___/",
    ]

    /// Ein Bild der Animation und wie lange es stehen bleibt (Sekunden).
    public struct Frame: Equatable, Sendable {
        public var text: String
        public var pause: Double
    }

    /// Ohne Terminal (etwa in einem Protokoll): Wagen und Satz ohne Farben.
    public static var plain: String {
        (car + [doneText]).joined(separator: "\n")
    }

    private static let pink = 205
    private static let gray = 245
    private static let smoke = 240
    private static let asphalt = 238
    private static let spokes: [Character] = ["-", "\\", "|", "/"]
    /// Wagen, Straße, Satz.
    private static var rows: Int { car.count + 2 }

    /// Alle Bilder für ein Terminal mit `columns` Spalten. Das erste blendet den Cursor aus, jedes weitere
    /// springt an den Anfang des vorigen zurück, das letzte zeigt den Satz und blendet den Cursor wieder ein.
    public static func frames(columns: Int) -> [Frame] {
        let width = min(max(columns, 50), 160)
        var frames: [Frame] = []
        func add(x: Int, spin: Int, exhaust: [Puff], text: String?, pause: Double) {
            let lead = frames.isEmpty ? "\u{1B}[?25l\n" : "\u{1B}[\(rows - 1)A\r"
            frames.append(Frame(text: lead + render(width: width, x: x, spin: spin, exhaust: exhaust, text: text),
                                pause: pause))
        }
        // Motor läuft: Der Auspuff qualmt.
        for tick in 0..<10 {
            let puffs = (1...(tick % 3 + 1)).map { Puff(column: 4 - $0 * 2, row: 3, symbol: $0 == 1 ? "~" : ".") }
            add(x: 2, spin: 0, exhaust: puffs, text: nil, pause: 0.07)
        }
        // Losfahren und beschleunigen, bis der Wagen rechts verschwunden ist; dahinter Fahrtwind.
        var x = 2.0, speed = 0.6, spin = 0
        while x < Double(width) {
            x += speed
            speed = min(speed * 1.12, 6)
            spin += 1
            let left = Int(x.rounded())
            let trail = (1...min(Int((speed * 2).rounded()), 10)).flatMap {
                [Puff(column: left - $0 * 2, row: 2, symbol: "-"), Puff(column: left - $0 * 3, row: 3, symbol: "=")]
            }
            add(x: left, spin: spin, exhaust: trail, text: nil, pause: 0.03)
        }
        add(x: width + 5, spin: spin, exhaust: [], text: doneText, pause: 0)
        frames[frames.count - 1].text += "\n\u{1B}[?25h"
        return frames
    }

    struct Puff {
        var column: Int
        var row: Int
        var symbol: Character
    }

    /// Ein Bild: Zellen mit Zeichen und 256er-Farbe, jede Zeile bis zum Rand gelöscht.
    private static func render(width: Int, x: Int, spin: Int, exhaust: [Puff], text: String?) -> String {
        let columns = width - 1
        var grid = Array(repeating: Array(repeating: Cell(symbol: " ", color: nil), count: columns), count: rows)
        let wheels = wheelColumns()
        for (row, line) in car.enumerated() {
            for (offset, character) in line.enumerated() {
                // Die Speichen in den Radkästen drehen sich.
                let symbol = row == 3 && wheels.hubs.contains(offset) ? spokes[spin % spokes.count] : character
                let column = x + offset
                guard symbol != " ", column >= 0, column < columns else { continue }
                let isWheel = row == 4 || (row == 3 && wheels.rims.contains(offset))
                grid[row][column] = Cell(symbol: symbol, color: isWheel ? gray : pink)
            }
        }
        for puff in exhaust where puff.column >= 0 && puff.column < columns && grid[puff.row][puff.column].symbol == " " {
            grid[puff.row][puff.column] = Cell(symbol: puff.symbol, color: smoke)
        }
        // Straße mit Mittelstreifen, die nach links zieht.
        for column in 0..<columns {
            grid[car.count][column] = Cell(symbol: (column + spin * 2) % 8 < 4 ? "-" : " ", color: asphalt)
        }
        if let text {
            let start = max((columns - text.count) / 2, 0)
            for (offset, character) in text.enumerated() where start + offset < columns {
                grid[car.count + 1][start + offset] = Cell(symbol: character, color: pink)
            }
        }
        return grid.map { cells in
            cells.map { cell in
                guard let color = cell.color else { return String(cell.symbol) }
                return "\u{1B}[38;5;\(color)m\(cell.symbol)\u{1B}[0m"
            }.joined() + "\u{1B}[K"
        }.joined(separator: "\n")
    }

    private struct Cell {
        var symbol: Character
        var color: Int?
    }

    /// Radkästen „/   \“ in der vierten Zeile: Speichen in der Mitte, das ganze Rad grau.
    private static func wheelColumns() -> (hubs: Set<Int>, rims: Set<Int>) {
        let line = Array(car[3])
        let starts = (0..<(line.count - 4)).filter { String(line[$0..<($0 + 5)]) == "/   \\" }
        return (Set(starts.map { $0 + 2 }), Set(starts.flatMap { $0...($0 + 4) }))
    }
}
