import Foundation
import Observation

/// Hält die Einstellungen im Speicher und schreibt sie bei jeder Änderung als JSON auf die Platte.
@MainActor @Observable
public final class SettingsStore {
    public var settings: AppSettings {
        didSet { save() }
    }

    @ObservationIgnored private let fileURL: URL
    /// Nach `freeze()` schreibt der Speicher nichts mehr (beim Zurücksetzen der App).
    @ObservationIgnored private var frozen = false

    /// Liest die Datei; fehlt sie oder ist sie kaputt, gelten die Standardwerte.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = .default
        }
    }

    public nonisolated static func defaultFileURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: "notchai", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }

    /// Ab jetzt nichts mehr schreiben: Die App wird gleich ohne Einstellungen neu gestartet.
    public func freeze() {
        frozen = true
    }

    private func save() {
        guard !frozen else { return }
        // Schreibfehler werden bewusst geschluckt: Einstellungen dürfen die App nie zum Absturz bringen.
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {}
    }
}
