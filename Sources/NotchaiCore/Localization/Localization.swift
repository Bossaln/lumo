import Foundation

/// Sprache der Oberfläche.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case german = "de"
    case english = "en"

    /// Name in der Sprache selbst, für die Auswahl.
    public var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// Die erste bevorzugte Sprache des Macs, die notchai kann; sonst Englisch.
    public static func preferred(from languages: [String]) -> AppLanguage {
        for language in languages {
            if let match = allCases.first(where: { language.lowercased().hasPrefix($0.rawValue) }) { return match }
        }
        return .english
    }

    /// Sprache eines Terminals aus `LC_ALL`, `LC_MESSAGES` und `LANG` (in dieser Reihenfolge); `nil`, wenn keine
    /// davon etwas sagt (etwa „C“).
    public static func fromEnvironment(_ environment: [String: String]) -> AppLanguage? {
        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            guard let value = environment[key], !value.isEmpty else { continue }
            return allCases.first { value.lowercased().hasPrefix($0.rawValue) }
        }
        return nil
    }
}

/// Übersetzt die Oberfläche. Im Code steht der deutsche Text; er ist zugleich der Schlüssel für die englische
/// Tabelle (`Localization.english`). Eingesetzte Werte stehen als `{0}`, `{1}` … im Text, damit sie im Englischen
/// an einer anderen Stelle stehen dürfen.
public enum Localization {
    private final class Current: @unchecked Sendable {
        let lock = NSLock()
        var language = AppLanguage.german
    }

    private static let current = Current()

    /// Sprache, in der `L(…)` übersetzt. Die App setzt sie beim Start und bei jeder Änderung der Einstellung.
    public static var language: AppLanguage {
        get {
            current.lock.lock()
            defer { current.lock.unlock() }
            return current.language
        }
        set {
            current.lock.lock()
            current.language = newValue
            current.lock.unlock()
        }
    }

    public static func text(_ german: String, in language: AppLanguage, _ arguments: [String] = []) -> String {
        var text = language == .english ? english[german] ?? german : german
        for (index, argument) in arguments.enumerated() {
            text = text.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        return text
    }

    /// Platzhalter eines Textes ({0}, {1} …), sortiert.
    static func placeholders(in text: String) -> [String] {
        text.matches(of: /\{\d+\}/).map { String($0.output) }.sorted()
    }
}

/// Text der Oberfläche in der eingestellten Sprache. `german` ist der Text, wie er im Deutschen lautet;
/// `arguments` ersetzen `{0}`, `{1}` …
public func L(_ german: String, _ arguments: Any...) -> String {
    Localization.text(german, in: Localization.language, arguments.map { "\($0)" })
}
