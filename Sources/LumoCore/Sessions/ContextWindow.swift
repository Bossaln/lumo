/// Größe des Kontextfensters und daraus der Füllstand für den Gedächtnis-Balken.
public enum ContextWindow {
    /// Modelle mit 1 000 000 Tokens Kontext; alle anderen haben 200 000.
    private static let oneMillionPrefixes = [
        "claude-fable", "claude-sonnet-5", "claude-haiku-5", "claude-opus-5",
        "claude-opus-4-7", "claude-opus-4-8", "claude-opus-4-9",
    ]

    public static func claudeLimit(model: String?) -> Int {
        guard let model else { return 200_000 }
        if model.contains("[1m]") || oneMillionPrefixes.contains(where: model.hasPrefix) { return 1_000_000 }
        return 200_000
    }

    /// Anteil `tokens / limit`, auf 0…1 begrenzt; `nil`, wenn etwas fehlt.
    public static func fraction(tokens: Int?, limit: Int?) -> Double? {
        guard let tokens, let limit, limit > 0 else { return nil }
        return min(max(Double(tokens) / Double(limit), 0), 1)
    }
}
