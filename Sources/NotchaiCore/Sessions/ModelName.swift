import Foundation

/// Lesbarer Name einer Modell-Kennung für die Detailansicht: `claude-opus-5-5` → „Opus 5.5“,
/// `claude-sonnet-4-5-20250929` → „Sonnet 4.5“. Unbekannte Kennungen bleiben wie sie sind.
public enum ModelName {
    public static func display(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        guard parts.first == "claude", parts.count >= 3 else { return id }
        parts.removeFirst()
        // Datum am Ende (20250929) und Zusätze wie „[1m]“ gehören nicht zum Namen.
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, family.allSatisfy(\.isLetter) else { return id }
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) }
        guard !version.isEmpty else { return id }
        return family.prefix(1).uppercased() + family.dropFirst() + " " + version.joined(separator: ".")
    }
}
