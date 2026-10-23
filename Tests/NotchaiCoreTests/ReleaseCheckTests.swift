import Foundation
import Testing
@testable import NotchaiCore

/// Antwort von `GET /repos/{owner}/{repo}/releases/latest`, gekürzt auf die Felder, die notchai liest.
private func latest(tag: String, body: String? = nil) -> Data {
    var json: [String: Any] = ["tag_name": tag, "html_url": "https://github.com/Bossaln/notchai/releases/tag/\(tag)",
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
    #expect(offer.pageURL == "https://github.com/Bossaln/notchai/releases/tag/v0.2.0")
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
    * Büro: Lagerhalle mit Autos by @Bossaln in https://github.com/Bossaln/notchai/pull/7
    - Musik: Spulen im Balken

    **Full Changelog**: https://github.com/Bossaln/notchai/compare/v0.1.0...v0.2.0
    """
    let state = ReleaseCheck.state(currentVersion: "0.1.0", response: latest(tag: "v0.2.0", body: body), viaHomebrew: false)
    guard case .releaseAvailable(let offer) = state else { Issue.record("erwartet neue Version, war \(state)"); return }
    #expect(offer.notes == ["Büro: Lagerhalle mit Autos", "Musik: Spulen im Balken"])
}
