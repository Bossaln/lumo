/// Setzt Text so in ein Shell-Kommando, dass Leerzeichen und Anführungszeichen nichts kaputtmachen.
public enum ShellQuote {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@%=,")

    public static func quote(_ text: String) -> String {
        guard text.isEmpty || !text.allSatisfy(safe.contains) else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
