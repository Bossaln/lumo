/// Begrüßung nach `brew install` und `brew upgrade`: die Szene aus `WelcomeScene` (MacBook, Leuchten, Signal,
/// Musik) und der Satz „lumo ist installiert – los geht's!“. Das Programm `lumo-welcome` schreibt die
/// Bilder ins Terminal; hier entstehen sie, damit sie sich ohne Terminal prüfen lassen.
public enum InstallGreeting {
    /// In der Sprache des Terminals (`lumo-welcome` setzt `Localization.language`).
    public static var doneText: String { L("lumo ist installiert – los geht's!") }
    public static var tipText: String { L("Öffne lumo im Programme-Ordner – die Einrichtung macht den Rest.") }

    /// Ein Bild der Animation und wie lange es stehen bleibt (Sekunden).
    public struct Frame: Equatable, Sendable {
        public var text: String
        public var pause: Double
    }

    /// Zeilen der Szene (Cursor hoch, um sie neu zu zeichnen).
    public static var rows: Int { WelcomeScene.height }

    /// Ohne Terminal (etwa in einem Protokoll): nur der Satz, ohne Farben.
    public static var plain: String { doneText + "\n" + tipText }

    /// Alle Bilder an Ort und Stelle (für Terminals unbekannter Höhe): Das erste blendet den Cursor aus, jedes
    /// weitere springt an den Anfang des vorigen zurück (Cursor hoch und in Spalte 1; kein Wagenrücklauf, den ein
    /// Pseudo-Terminal zu einem Zeilenumbruch machen könnte), das letzte zeigt den Satz und blendet den Cursor ein.
    public static func frames(columns: Int) -> [Frame] {
        var frames = WelcomeScene(columns: columns).frames().enumerated().map { index, frame in
            Frame(text: (index == 0 ? "\u{1B}[?25l\n" : "\u{1B}[\(rows - 1)A\u{1B}[1G") + frame.text, pause: frame.pause)
        }
        frames[frames.count - 1].text += "\n\u{1B}[?25h"
        return frames
    }

    /// Vollbild: die Szene mittig auf einer eigenen Bildschirmseite, danach kommt die vorige zurück und der Satz
    /// steht im normalen Verlauf. `nil`, wenn das Terminal zu niedrig ist; dann zeichnet `frames(columns:)`.
    public static func fullscreenFrames(columns: Int, rows terminalRows: Int) -> (frames: [Frame], closing: String)? {
        guard terminalRows >= rows + 2 else { return nil }
        let top = (terminalRows - rows) / 2 + 1
        let frames = WelcomeScene(columns: columns).frames().enumerated().map { index, frame in
            Frame(text: (index == 0 ? "\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J" : "") + "\u{1B}[\(top);1H" + frame.text, pause: frame.pause)
        }
        let closing = "\u{1B}[?1049l\u{1B}[?25h\u{1B}[38;5;\(WelcomeScene.pink)m\(doneText)\u{1B}[0m\n\u{1B}[38;5;\(WelcomeScene.gray)m\(tipText)\u{1B}[0m\n"
        return (frames, closing)
    }

    /// Läuft die Begrüßung unter lumo selbst (Update über den Knopf)? Dann schreibt Homebrew alles ins Protokoll,
    /// und statt der Szene reicht der Satz. `lookup` liefert zu einer Prozess-ID den Elternprozess und den Namen.
    public static func isRunByLumo(pid: Int32, lookup: (Int32) -> (parent: Int32, name: String)?) -> Bool {
        var current = pid
        var seen: Set<Int32> = []
        while current > 1, seen.insert(current).inserted, let process = lookup(current) {
            if process.name == "lumo" { return true }
            current = process.parent
        }
        return false
    }
}
