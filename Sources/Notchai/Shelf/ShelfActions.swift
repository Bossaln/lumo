import AppKit
import NotchaiCore
import SwiftUI
import UniformTypeIdentifiers

/// Wohin eine über die Notch gezogene Datei geht.
enum ShelfTarget: String, CaseIterable, Identifiable {
    case airDrop, shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airDrop: "AirDrop"
        case .shelf: L("Ablage")
        }
    }

    var subtitle: String {
        switch self {
        case .airDrop: L("An ein Gerät in der Nähe")
        case .shelf: L("Kurz hier lagern")
        }
    }

    /// Steht unter dem Titel, solange die Datei über dem Ziel schwebt.
    var releaseHint: String {
        switch self {
        case .airDrop: L("Loslassen zum Senden")
        case .shelf: L("Loslassen zum Ablegen")
        }
    }

    var symbol: String {
        switch self {
        case .airDrop: "dot.radiowaves.left.and.right"
        case .shelf: "tray.and.arrow.down.fill"
        }
    }

    var color: Color {
        switch self {
        case .airDrop: Color(.sRGB, red: 0.04, green: 0.52, blue: 1.0)
        case .shelf: Color(.sRGB, red: 1.0, green: 0.62, blue: 0.04)
        }
    }
}

/// Was mit abgelegten und gezogenen Dateien passiert: Ablegen, per AirDrop senden, öffnen, im Finder zeigen.
@MainActor
enum ShelfActions {
    /// Liest die Dateien aus einem Drop und gibt sie an das Ziel weiter. Danach zeigt die Ablage wieder
    /// ihre Dateien, auch wenn macOS das Loslassen nicht eigens meldet.
    static func receive(_ providers: [NSItemProvider], for target: ShelfTarget, model: AppModel) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                if let url = await fileURL(from: provider) { urls.append(url) }
            }
            model.send(.fileDragEnded)
            guard !urls.isEmpty else { return }
            switch target {
            case .shelf: model.shelfStore.add(urls.map(\.path))
            case .airDrop: airDrop(urls, model: model)
            }
        }
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    /// Öffnet den AirDrop-Dialog von macOS mit den Dateien.
    static func airDrop(_ urls: [URL], model: AppModel) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            model.showNotice(L("AirDrop ist gerade nicht verfügbar"))
            return
        }
        // Ohne aktive App bliebe der Dialog hinter dem vorderen Fenster.
        NSApp.activate()
        service.perform(withItems: urls)
    }

    static func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    static func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Symbol einer Datei, wie der Finder es zeigt; einmal geladen bleibt es im Speicher.
    static func icon(for path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    private static var icons: [String: NSImage] = [:]
}
