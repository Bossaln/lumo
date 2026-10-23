import Foundation

/// Updates für Builds ohne Quellordner: vergleicht die eigene Version mit der neuesten Version auf GitHub
/// (`releases/latest`). Gesendet wird dabei nur diese eine Abfrage, keine Daten über den Mac.
public enum ReleaseCheck {
    public static let repository = "Bossaln/notchai"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Ordnet die Antwort von `releases/latest` ein.
    public static func state(currentVersion: String, response: Data, viaHomebrew: Bool) -> UpdateState {
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = object["html_url"] as? String else {
            return .failed("GitHub hat keine lesbare Version geliefert.")
        }
        guard isNewer(tag, than: currentVersion) else { return .upToDate }
        let notes = notes(from: object["body"] as? String ?? "")
        return .releaseAvailable(ReleaseOffer(version: plain(tag), pageURL: page, notes: notes, viaHomebrew: viaHomebrew))
    }

    /// `true`, wenn `candidate` eine höhere Versionsnummer hat (Zahlen werden einzeln verglichen, „v“ zählt nicht).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = numbers(candidate), let old = numbers(current) else { return false }
        for i in 0..<max(new.count, old.count) {
            let a = i < new.count ? new[i] : 0, b = i < old.count ? old[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Shell-Befehl für das Update über Homebrew. Erst `brew update`: Sonst kennt Homebrew die neue Version aus dem
    /// Tap bis zu 24 Stunden lang nicht. Homebrew beendet notchai beim Upgrade selbst (`uninstall quit:` im Cask);
    /// nur nach erfolgreichem Upgrade öffnet der Befehl die neue Version.
    public static func homebrewUpgradeScript(brew: String, log: String, app: String) -> String {
        let brew = ShellQuote.quote(brew), log = ShellQuote.quote(log)
        return "\(brew) update >> \(log) 2>&1; \(brew) upgrade --cask notchai >> \(log) 2>&1 && open \(ShellQuote.quote(app))"
    }

    private static func plain(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func numbers(_ version: String) -> [Int]? {
        let parts = plain(version).split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    /// Aufzählungspunkte aus den Versionshinweisen, ohne GitHubs Anhang „by @… in https://…“.
    static func notes(from body: String) -> [String] {
        body.split(separator: "\n").compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("* ") || text.hasPrefix("- ") else { return nil }
            var item = String(text.dropFirst(2))
            if let range = item.range(of: #" by @\S+ in https?://\S+$"#, options: .regularExpression) {
                item.removeSubrange(range)
            }
            return item.isEmpty ? nil : item
        }
        .prefix(6).map { $0 }
    }
}
