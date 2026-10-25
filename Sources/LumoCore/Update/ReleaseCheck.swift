import Foundation

/// Updates für Builds ohne Quellordner: vergleicht die eigene Version mit der neuesten Version auf GitHub
/// (`releases/latest`). Gesendet wird dabei nur diese eine Abfrage, keine Daten über den Mac.
public enum ReleaseCheck {
    public static let repository = "Bossaln/lumo"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// Ohne Schnittstelle und ohne Abfragelimit: GitHub leitet auf die Seite der neuesten Version weiter
    /// (`…/releases/tag/vX.Y.Z`). Ersatz, wenn die Schnittstelle nicht antwortet (etwa 403 bei zu vielen Abfragen).
    public static let latestPageURL = URL(string: "https://github.com/\(repository)/releases/latest")!
    /// Voll qualifiziert, damit Homebrew den Cask bei jedem Aufruf als vertrauenswürdig einträgt (seit Homebrew 6
    /// lädt es Casks aus fremden Taps sonst nicht) und ein gleichnamiger Cask aus einem anderen Tap nie dazwischenkommt.
    public static let cask = "bossaln/tap/lumo"
    public static let upgradeCommand = "brew update && brew upgrade --cask \(cask)"
    /// Länger wartet die App nicht auf Homebrew (Netz weg, hängende Abfrage).
    public static let upgradeTimeout: TimeInterval = 20 * 60

    /// Umgebung für brew aus der App heraus: fester `PATH` statt der Login-Shell (deren Profil könnte hängen oder
    /// fragen), kein eigenes Auto-Update (wir rufen `brew update` selbst), keine Hinweise, kein Aufräumen fremder Pakete.
    public static func homebrewEnvironment(brew: String, base: [String: String]) -> [String: String] {
        var env = base
        let brewDir = (brew as NSString).deletingLastPathComponent
        env["PATH"] = "\(brewDir):/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        return env
    }

    /// Version aus der Seite der neuesten Version (`https://github.com/…/releases/tag/v0.8.0` → `0.8.0`);
    /// `nil`, wenn die Adresse keine Versionsseite ist (etwa `…/releases` ohne einzige Version).
    public static func version(fromReleasePage url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.lastIndex(of: "tag"), index + 1 < parts.count else { return nil }
        let version = plain(parts[index + 1])
        return numbers(version) == nil ? nil : version
    }

    /// Ordnet die Weiterleitung von `latestPageURL` ein; `nil`, wenn sie keine Version nennt.
    public static func state(currentVersion: String, releasePage: URL, viaHomebrew: Bool) -> UpdateState? {
        guard let version = version(fromReleasePage: releasePage) else { return nil }
        guard isNewer(version, than: currentVersion) else { return .upToDate }
        return .releaseAvailable(ReleaseOffer(version: version, pageURL: releasePage.absoluteString, notes: [],
                                              viaHomebrew: viaHomebrew))
    }

    /// Ordnet die Antwort von `releases/latest` ein.
    public static func state(currentVersion: String, response: Data, viaHomebrew: Bool) -> UpdateState {
        guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = object["html_url"] as? String else {
            return .failed(L("GitHub hat keine lesbare Version geliefert."))
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
    /// Tap bis zu 24 Stunden lang nicht. Läuft brew in lumo, beendet Homebrew lumo nicht („brew is running inside
    /// it“); die App prüft danach selbst die installierte Version und startet neu (`upgradeOutcome`). Hat ein älteres
    /// Homebrew lumo doch beendet, öffnet der Befehl die neue Version. Endet mit dem Ergebnis von `brew upgrade`.
    public static func homebrewUpgradeScript(brew: String, log: String, app: String, appPID: Int32) -> String {
        let brew = ShellQuote.quote(brew), log = ShellQuote.quote(log), app = ShellQuote.quote(app)
        return [
            "echo \"=== lumo-Update $(date '+%Y-%m-%d %H:%M:%S') ===\" >> \(log)",
            "\(brew) update >> \(log) 2>&1",
            "\(brew) upgrade --cask \(cask) >> \(log) 2>&1",
            "status=$?",
            "kill -0 \(appPID) 2>/dev/null || { [ $status -eq 0 ] && open \(app); }",
            "exit $status",
        ].joined(separator: "; ")
    }

    /// Wartet, bis die alte App beendet ist, und öffnet dann die neue.
    public static func relaunchScript(pid: Int32, app: String) -> String {
        "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \(ShellQuote.quote(app))"
    }

    /// Wie das Homebrew-Update ausging.
    public enum UpgradeOutcome: Equatable, Sendable {
        /// Die neue Version liegt im Programme-Ordner; lumo startet neu.
        case relaunch
        case failed(String)
    }

    /// Bewertet das Update nach dem, was jetzt installiert ist: Ist die App im Programme-Ordner neuer als die laufende,
    /// hat es geklappt, egal worüber brew danach noch gestolpert ist.
    public static func upgradeOutcome(exitStatus: Int32, installedVersion: String?, runningVersion: String,
                                      offeredVersion: String) -> UpgradeOutcome {
        if let installedVersion, isNewer(installedVersion, than: runningVersion) { return .relaunch }
        let command = upgradeCommand
        if exitStatus != 0 || installedVersion == nil {
            return .failed(L("Homebrew hat lumo nicht aktualisiert. Details im Protokoll; im Terminal geht es mit „{0}“.",
                             command))
        }
        return .failed(L("Homebrew kennt Version {0} noch nicht. Versuch es gleich noch einmal oder im Terminal mit „{1}“.",
                         offeredVersion, command))
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
