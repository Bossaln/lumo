import Foundation
import Observation

/// Eine abgelegte Datei. notchai merkt sich nur den Pfad; die Datei bleibt, wo sie ist.
public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public var path: String
    public var addedAt: Date

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent }
}

/// Reiter „Ablage“: Dateien, die man auf die Notch zieht, um sie kurz zu lagern und später wieder
/// herauszuziehen. Die neuesten stehen vorn.
public struct Shelf: Codable, Equatable, Sendable {
    /// Mehr Dateien passen nicht sinnvoll in die Notch; die ältesten fallen heraus.
    public static let limit = 40

    public private(set) var items: [ShelfItem] = []

    public init() {}

    /// Legt Dateien vorn ab. Schon abgelegte rücken nach vorn, statt doppelt zu erscheinen.
    /// Gibt die abgelegten Pfade zurück (ohne Doppelte).
    @discardableResult
    public mutating func add(_ paths: [String], now: Date) -> [String] {
        var seen = Set<String>()
        let fresh = paths.filter { seen.insert($0).inserted }
        items.removeAll { seen.contains($0.path) }
        items.insert(contentsOf: fresh.map { ShelfItem(path: $0, addedAt: now) }, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        return fresh
    }

    public mutating func remove(_ path: String) {
        items.removeAll { $0.path == path }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Entfernt Einträge, deren Datei es nicht mehr gibt; `true`, wenn sich etwas geändert hat.
    @discardableResult
    public mutating func prune(exists: (String) -> Bool) -> Bool {
        let before = items.count
        items.removeAll { !exists($0.path) }
        return items.count != before
    }
}

/// Hält die Ablage und schreibt sie bei jeder Änderung als JSON auf die Platte, damit sie einen Neustart
/// (etwa ein Update) übersteht. Beim Laden fallen Dateien heraus, die es nicht mehr gibt.
@MainActor @Observable
public final class ShelfStore {
    public private(set) var shelf: Shelf

    @ObservationIgnored private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        var shelf = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Shelf.self, from: $0) } ?? Shelf()
        let pruned = shelf.prune { FileManager.default.fileExists(atPath: $0) }
        self.shelf = shelf
        if pruned { save() }
    }

    public nonisolated static func defaultFileURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "notchai", directoryHint: .isDirectory)
            .appending(path: "shelf.json")
    }

    public func add(_ paths: [String]) {
        shelf.add(paths, now: Date())
        save()
    }

    public func remove(_ path: String) {
        shelf.remove(path)
        save()
    }

    public func removeAll() {
        shelf.removeAll()
        save()
    }

    /// Wirft Einträge hinaus, deren Datei inzwischen gelöscht oder verschoben wurde.
    public func pruneMissing() {
        if shelf.prune(exists: { FileManager.default.fileExists(atPath: $0) }) { save() }
    }

    private func save() {
        // Schreibfehler werden geschluckt: Die Ablage darf die App nie zum Absturz bringen.
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(shelf).write(to: fileURL, options: .atomic)
        } catch {}
    }
}
