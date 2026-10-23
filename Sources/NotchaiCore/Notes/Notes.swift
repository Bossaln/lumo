import Foundation
import Observation

/// Eine Schnellnotiz aus der Notch.
public struct QuickNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Reiter „Notizen“: Schnellnotizen, die neuesten vorn. Zweimal ⌃ öffnet ein Feld für eine neue.
public struct NoteBook: Codable, Equatable, Sendable {
    /// Mehr hält die Notch nicht vor; die ältesten fallen heraus.
    public static let limit = 200

    public private(set) var notes: [QuickNote] = []

    public init() {}

    /// Legt eine Notiz vorn ab; Leerzeichen am Rand fallen weg, leere Notizen werden nicht gespeichert.
    @discardableResult
    public mutating func add(_ text: String, now: Date) -> QuickNote? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let note = QuickNote(text: text, createdAt: now)
        notes.insert(note, at: 0)
        if notes.count > Self.limit { notes.removeLast(notes.count - Self.limit) }
        return note
    }

    public mutating func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        notes.removeAll()
    }
}

/// Hält die Notizen und schreibt sie bei jeder Änderung als JSON auf die Platte (nur auf diesem Mac).
@MainActor @Observable
public final class NoteStore {
    public private(set) var book: NoteBook

    @ObservationIgnored private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        book = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(NoteBook.self, from: $0) } ?? NoteBook()
    }

    public nonisolated static func defaultFileURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "notchai", directoryHint: .isDirectory)
            .appending(path: "notes.json")
    }

    @discardableResult
    public func add(_ text: String) -> QuickNote? {
        guard let note = book.add(text, now: Date()) else { return nil }
        save()
        return note
    }

    public func remove(_ id: UUID) {
        book.remove(id)
        save()
    }

    public func removeAll() {
        book.removeAll()
        save()
    }

    private func save() {
        // Schreibfehler werden geschluckt: Notizen dürfen die App nie zum Absturz bringen.
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: fileURL, options: .atomic)
        } catch {}
    }
}
