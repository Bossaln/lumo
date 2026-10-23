/// Erkennt, ob gerade irgendwo auf dem Mac Dateien gezogen werden (aus Maus-Ereignissen und dem
/// Drag-Zwischenspeicher von macOS). Beginnt ein Ziehen, schreibt die Quelle neu in den Zwischenspeicher;
/// sein Zähler ändert sich dann gegenüber dem Klick. Fenster verschieben oder Text markieren zählt nicht.
public struct FileDragTracker: Sendable {
    public private(set) var isDraggingFiles = false
    private var changeCountAtStart: Int?
    /// Das Ziehen begann in notchai selbst (eine Datei aus der Ablage heraus).
    private var startedInNotchai = false

    public init() {}

    public mutating func mouseDown(changeCount: Int, insideNotchai: Bool) {
        isDraggingFiles = false
        changeCountAtStart = changeCount
        startedInNotchai = insideNotchai
    }

    /// Bei jeder Bewegung mit gedrückter Maustaste; `true`, solange Dateien gezogen werden.
    public mutating func dragged(changeCount: Int, hasFiles: Bool) -> Bool {
        if isDraggingFiles { return true }
        guard let start = changeCountAtStart else {
            // Den Klick nicht gesehen: ab jetzt zählt der aktuelle Stand.
            changeCountAtStart = changeCount
            return false
        }
        if changeCount != start, hasFiles, !startedInNotchai { isDraggingFiles = true }
        return isDraggingFiles
    }

    /// Maustaste losgelassen; `true`, wenn damit ein Ziehen von Dateien endet.
    public mutating func mouseUp() -> Bool {
        defer {
            isDraggingFiles = false
            changeCountAtStart = nil
            startedInNotchai = false
        }
        return isDraggingFiles
    }
}
