import Foundation

/// Liest an JSONL-Dateien nur an, was seit dem letzten Mal dazugekommen ist. Eine halb geschriebene
/// letzte Zeile wartet, bis ihr Zeilenende da ist; wird die Datei kürzer, beginnt das Lesen von vorn.
/// Nicht threadsicher: gehört einer seriellen Warteschlange (`TranscriptLibrary`).
public final class TranscriptTailer {
    /// Mehr wird pro Aufruf nicht gelesen; große Transkripte kommen so über mehrere Durchläufe herein.
    static let chunkLimit = 16 << 20

    private struct FileState {
        var offset: UInt64 = 0
        var partial = Data()
        var restarted = false
    }

    private var files: [String: FileState] = [:]

    public init() {}

    /// Neue vollständige Zeilen ohne Zeilenende; leere Zeilen fallen weg.
    public func readNewLines(at url: URL) -> [Data] {
        let path = url.path
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber else {
            files[path] = nil
            return []
        }
        var state = files[path] ?? FileState()
        state.restarted = false
        if size.uint64Value < state.offset {
            state = FileState(restarted: true)
        }
        guard size.uint64Value > state.offset, let handle = try? FileHandle(forReadingFrom: url) else {
            files[path] = state
            return []
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let chunk = try? handle.read(upToCount: Self.chunkLimit), !chunk.isEmpty else {
            files[path] = state
            return []
        }
        state.offset += UInt64(chunk.count)
        var data = state.partial + chunk
        var lines: [Data] = []
        while let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            let line = data[data.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            data = data[(newline + 1)...]
        }
        state.partial = Data(data)
        files[path] = state
        return lines
    }

    /// Hat der letzte Aufruf für `url` von vorn begonnen, weil die Datei kürzer wurde?
    public func wasRestarted(_ url: URL) -> Bool {
        files[url.path]?.restarted ?? false
    }

    /// Vergisst eine Datei (sie ist zu alt geworden oder verschwunden).
    public func forget(_ url: URL) {
        files[url.path] = nil
    }
}
