import Foundation

/// „Letzte Hook-Ereignisse kopieren“ (Entwickler-Seite): Der Text landet in Issues und Chats. Er zeigt deshalb, was
/// zur Diagnose zählt (Ereignis, Zeit, Felder, Umgebung), aber keine Zugangsdaten und keine ganzen Inhalte.
public enum HookExport {
    /// So viele Zeichen bleiben von Prompts, Antworten und Werkzeug-Eingaben stehen.
    static let textLength = 80
    private static let secretWords = ["TOKEN", "AUTH", "CAPABILITY", "SECRET", "PASSWORD", "PASSWD", "KEY", "COOKIE"]

    /// Klingt der Name einer Umgebungsvariablen nach Zugangsdaten?
    public static func isSecretName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return secretWords.contains { upper.contains($0) }
    }

    /// Kopie des Ereignisses für die Zwischenablage: geheime Werte ersetzt, lange Texte gekürzt (mit Länge).
    public static func redacted(_ envelope: HookEnvelope) -> HookEnvelope {
        var copy = envelope
        copy.env = envelope.env.reduce(into: [:]) { result, entry in
            result[entry.key] = isSecretName(entry.key) ? "‹entfernt›" : entry.value
        }
        var event = envelope.event
        event.prompt = event.prompt.map(shorten)
        event.lastAssistantMessage = event.lastAssistantMessage.map(shorten)
        event.message = event.message.map(shorten)
        event.error = event.error.map(shorten)
        event.toolInput = event.toolInput.map(shorten)
        copy.event = event
        return copy
    }

    private static func shorten(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let text): .string(shorten(text))
        case .array(let items): .array(items.map(shorten))
        case .object(let fields): .object(fields.mapValues(shorten))
        default: value
        }
    }

    private static func shorten(_ text: String) -> String {
        text.count > textLength ? String(text.prefix(textLength)) + "… (\(text.count) Zeichen)" : text
    }
}
