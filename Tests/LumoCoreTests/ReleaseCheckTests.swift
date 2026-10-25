import Foundation
import Testing
@testable import LumoCore

/// Antwort von `GET /repos/{owner}/{repo}/releases/latest`, gekürzt auf die Felder, die lumo liest.
private func latest(tag: String, body: String? = nil) -> Data {
    var json: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/Bossaln/lumo/releases/tag/\(tag)",
                               "draft": false, "prerelease": false]
    if let body { json["body"] = body }
    return try! JSONSerialization.data(withJSONObject: json)
}

@Test func releaseVersionsCompareNumerically() {
    #expect(ReleaseCheck.isNewer("0.10.0", than: "0.9.1"))
    #expect(ReleaseCheck.isNewer("v1.0", than: "0.9.9"))
    #expect(ReleaseCheck.isNewer("0.2.1", than: "0.2"))
    #expect(!ReleaseCheck.isNewer("v0.2.0", than: "0.2.0"))
    #expect(!ReleaseCheck.isNewer("0.1.9", than: "0.2.0"))
    // Unlesbare Versionen gelten nie als neuer.
    #expect(!ReleaseCheck.isNewer("nightly", than: "0.1.0"))
}

@Test func newerReleaseIsOffered() {
    let state = ReleaseCheck.state(currentVersion: "0.1.0", response: latest(tag: "v0.2.0"), viaHomebrew: true)
    guard case .releaseAvailable(let offer) = state else { Issue.record("erwartet neue Version, war \(state)"); return }
    #expect(offer.version == "0.2.0")
    #expect(offer.pageURL == "https://github.com/Bossaln/lumo/releases/tag/v0.2.0")
    #expect(offer.viaHomebrew)
}

@Test func sameOrOlderReleaseIsUpToDate() {
    #expect(ReleaseCheck.state(currentVersion: "0.2.0", response: latest(tag: "v0.2.0"), viaHomebrew: false) == .upToDate)
    #expect(ReleaseCheck.state(currentVersion: "0.3.0", response: latest(tag: "v0.2.0"), viaHomebrew: false) == .upToDate)
}

@Test func unreadableReleaseIsAFailure() {
    let state = ReleaseCheck.state(currentVersion: "0.1.0", response: Data("<html>".utf8), viaHomebrew: false)
    guard case .failed = state else { Issue.record("erwartet Fehler, war \(state)"); return }
}

@Test func releaseNotesBecomeShortBullets() {
    let body = """
    ## What's Changed
    * Büro: Lagerhalle mit Autos by @Bossaln in https://github.com/Bossaln/lumo/pull/7
    - Musik: Spulen im Balken

    **Full Changelog**: https://github.com/Bossaln/lumo/compare/v0.1.0...v0.2.0
    """
    let state = ReleaseCheck.state(currentVersion: "0.1.0", response: latest(tag: "v0.2.0", body: body), viaHomebrew: false)
    guard case .releaseAvailable(let offer) = state else { Issue.record("erwartet neue Version, war \(state)"); return }
    #expect(offer.notes == ["Büro: Lagerhalle mit Autos", "Musik: Spulen im Balken"])
}

@Test func homebrewUpdateRefreshesTheTapBeforeUpgrading() {
    let script = ReleaseCheck.homebrewUpgradeScript(brew: "/opt/homebrew/bin/brew", log: "/Users/x/update.log",
                                                    app: "/Applications/lumo.app", appPID: 4242)
    // Ohne `brew update` kennt Homebrew die neue Version bis zu 24 Stunden lang nicht.
    let update = script.range(of: "/opt/homebrew/bin/brew update")
    // Voll qualifiziert: trägt den Cask als vertrauenswürdig ein (Homebrew 6+) und meint nie einen fremden „lumo“.
    let upgrade = script.range(of: "/opt/homebrew/bin/brew upgrade --cask bossaln/tap/lumo")
    #expect(update != nil && upgrade != nil)
    if let update, let upgrade { #expect(update.lowerBound < upgrade.lowerBound) }
    // Alles landet im Protokoll, und der Befehl endet mit dem Ergebnis von `brew upgrade`.
    #expect(script.components(separatedBy: ">> /Users/x/update.log 2>&1").count == 3)
    #expect(script.contains("status=$?"))
    #expect(script.hasSuffix("exit $status"))
}

@Test func homebrewUpdateOpensTheAppOnlyIfHomebrewQuitIt() {
    // Läuft brew in lumo, beendet Homebrew lumo nicht („brew is running inside it“); dann startet die App
    // selbst neu. Hat ein älteres Homebrew lumo doch beendet, öffnet der Befehl die neue Version.
    let script = ReleaseCheck.homebrewUpgradeScript(brew: "/opt/homebrew/bin/brew", log: "/tmp/u.log",
                                                    app: "/Applications/lumo.app", appPID: 4242)
    #expect(script.contains("kill -0 4242 2>/dev/null || { [ $status -eq 0 ] && open /Applications/lumo.app; }"))
}

@Test func relaunchWaitsForTheOldAppToQuit() {
    let script = ReleaseCheck.relaunchScript(pid: 4242, app: "/Applications/lumo.app")
    #expect(script == "while kill -0 4242 2>/dev/null; do sleep 0.2; done; open /Applications/lumo.app")
}

// MARK: - Ergebnis des Homebrew-Updates

@Test func newerInstalledVersionMeansRelaunch() {
    #expect(ReleaseCheck.upgradeOutcome(exitStatus: 0, installedVersion: "0.5.0", runningVersion: "0.4.0",
                                        offeredVersion: "0.5.0") == .relaunch)
    // Auch wenn brew am Ende über etwas anderes stolpert (etwa beim Aufräumen): Die neue Version ist da.
    #expect(ReleaseCheck.upgradeOutcome(exitStatus: 1, installedVersion: "0.5.0", runningVersion: "0.4.0",
                                        offeredVersion: "0.5.0") == .relaunch)
}

@Test func failedUpgradeKeepsTheOldVersion() {
    let outcome = ReleaseCheck.upgradeOutcome(exitStatus: 1, installedVersion: "0.4.0", runningVersion: "0.4.0",
                                              offeredVersion: "0.5.0")
    guard case .failed(let message) = outcome else { Issue.record("erwartet Fehler, war \(outcome)"); return }
    #expect(message.contains("brew update && brew upgrade --cask bossaln/tap/lumo"))
}

@Test func homebrewThatDoesNotKnowTheVersionYetIsExplained() {
    let outcome = ReleaseCheck.upgradeOutcome(exitStatus: 0, installedVersion: "0.4.0", runningVersion: "0.4.0",
                                              offeredVersion: "0.5.0")
    guard case .failed(let message) = outcome else { Issue.record("erwartet Fehler, war \(outcome)"); return }
    #expect(message.contains("0.5.0"))
}

@Test func unreadableInstalledAppIsAFailure() {
    let outcome = ReleaseCheck.upgradeOutcome(exitStatus: 0, installedVersion: nil, runningVersion: "0.4.0",
                                              offeredVersion: "0.5.0")
    guard case .failed = outcome else { Issue.record("erwartet Fehler, war \(outcome)"); return }
}

// MARK: - Versionsseite als Ersatz für die Schnittstelle

@Test func releasePageRedirectNamesTheVersion() {
    #expect(ReleaseCheck.version(fromReleasePage: URL(string: "https://github.com/Bossaln/lumo/releases/tag/v0.8.0")!) == "0.8.0")
    #expect(ReleaseCheck.version(fromReleasePage: URL(string: "https://github.com/Bossaln/lumo/releases/tag/0.10.2")!) == "0.10.2")
    // Ohne einzige Version landet man auf der Übersicht; ein Tag ohne Zahlen ist keine Version.
    #expect(ReleaseCheck.version(fromReleasePage: URL(string: "https://github.com/Bossaln/lumo/releases")!) == nil)
    #expect(ReleaseCheck.version(fromReleasePage: URL(string: "https://github.com/Bossaln/lumo/releases/tag/preview")!) == nil)
}

@Test func releasePageStateMatchesTheApi() {
    let page = URL(string: "https://github.com/Bossaln/lumo/releases/tag/v0.8.0")!
    #expect(ReleaseCheck.state(currentVersion: "0.7.0", releasePage: page, viaHomebrew: true)
            == .releaseAvailable(ReleaseOffer(version: "0.8.0", pageURL: page.absoluteString, notes: [], viaHomebrew: true)))
    #expect(ReleaseCheck.state(currentVersion: "0.8.0", releasePage: page, viaHomebrew: true) == .upToDate)
    #expect(ReleaseCheck.state(currentVersion: "0.7.0", releasePage: URL(string: "https://github.com/Bossaln/lumo/releases")!,
                               viaHomebrew: true) == nil)
}

@Test func homebrewRunsWithAFixedPathAndWithoutItsOwnAutoUpdate() {
    let env = ReleaseCheck.homebrewEnvironment(brew: "/opt/homebrew/bin/brew", base: ["HOME": "/Users/x", "PATH": "/weird"])
    #expect(env["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    #expect(env["HOME"] == "/Users/x")
    #expect(env["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    #expect(env["HOMEBREW_NO_INSTALL_CLEANUP"] == "1")
}
