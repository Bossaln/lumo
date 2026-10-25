import Foundation

/// Eingabe von Breiten- und Längengrad im Einstellungsfenster: Komma oder Punkt, leer heißt „kein Wert“.
public enum CoordinateInput: Sendable {
    case latitude, longitude

    public enum Result: Equatable, Sendable {
        /// Feld leer: gespeicherten Wert entfernen.
        case empty
        case value(Double)
        /// Keine Zahl oder außerhalb des Bereichs: gespeicherten Wert behalten.
        case invalid
    }

    public var range: ClosedRange<Double> {
        switch self {
        case .latitude: -90...90
        case .longitude: -180...180
        }
    }

    public func parse(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // Nur Ziffern, ein Vorzeichen und ein Dezimaltrenner; schließt "nan", "inf" und "1e5" aus.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.".contains($0)) }),
              let value = Double(normalized), value.isFinite, range.contains(value) else { return .invalid }
        return .value(value)
    }

    /// Hinweis unter dem Feld, wenn die Eingabe nicht übernommen wird.
    public var invalidHint: String {
        switch self {
        case .latitude: L("Breitengrad: Zahl von −90 bis 90, z. B. 52,52")
        case .longitude: L("Längengrad: Zahl von −180 bis 180, z. B. 13,40")
        }
    }

    /// Anzeige mit deutschem Dezimalkomma, ohne überflüssige Nullen.
    public static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.locale(Locale(identifier: "de_DE")).grouping(.never)
            .precision(.fractionLength(0...6)))
    }
}
