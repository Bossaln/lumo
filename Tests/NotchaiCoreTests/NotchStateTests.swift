import Testing
@testable import NotchaiCore

@Test func hoverOpensLastTab() {
    var s = NotchState(); s.lastTab = .music
    s.apply(.hoverBegan, style: .island)
    #expect(s.mode == .panel(.music))
}
@Test func signalFromIdleUsesStyle() {
    var s = NotchState(); s.apply(.signalRaised, style: .banner)
    #expect(s.mode == .signal(.banner)); #expect(s.hasPendingSignal)
}
@Test func signalWhilePanelOpenShowsAfterHoverEnds() {
    var s = NotchState(); s.apply(.hoverBegan, style: .island)
    s.apply(.signalRaised, style: .island)
    #expect(s.mode == .panel(.sessions))
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .signal(.island))
}
@Test func islandExpandsToBannerAndFallsBack() {
    var s = NotchState(); s.apply(.signalRaised, style: .island)
    s.apply(.islandClicked, style: .island); #expect(s.mode == .signal(.banner))
    s.apply(.hoverEnded, style: .island); #expect(s.mode == .signal(.island))
}
@Test func bannerStaysOnHover() {
    var s = NotchState(); s.apply(.signalRaised, style: .vertical)
    s.apply(.hoverBegan, style: .vertical); #expect(s.mode == .signal(.vertical))
}
@Test func clearingSignalReturnsToIdle() {
    var s = NotchState(); s.apply(.signalRaised, style: .island)
    s.apply(.signalCleared, style: .island)
    #expect(s.mode == .idle); #expect(!s.hasPendingSignal)
}
@Test func tabSelectionIsRemembered() {
    var s = NotchState(); s.apply(.hoverBegan, style: .island)
    s.apply(.tabSelected(.office), style: .island)
    s.apply(.hoverEnded, style: .island); s.apply(.hoverBegan, style: .island)
    #expect(s.mode == .panel(.office))
}

// Antwort tippen: Solange das Antwortfeld die Tastatur hat, klappt das Signal nicht zu.
private func typingInClickedIsland() -> NotchState {
    var s = NotchState(); s.apply(.signalRaised, style: .island)
    s.apply(.islandClicked, style: .island)
    s.apply(.editingBegan, style: .island)
    return s
}
@Test func typingKeepsBannerOpenWhenPointerLeaves() {
    var s = typingInClickedIsland()
    #expect(s.isEditing)
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .signal(.banner))
}
@Test func collapseWaitsUntilTypingEnds() {
    var s = typingInClickedIsland()
    s.apply(.hoverEnded, style: .island)
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .signal(.island)); #expect(!s.isEditing)
}
@Test func typingEndedWithPointerBackKeepsBanner() {
    var s = typingInClickedIsland()
    s.apply(.hoverEnded, style: .island)
    s.apply(.hoverBegan, style: .island)
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .signal(.banner))
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .signal(.island))
}
@Test func typingEndedWithPointerInsideKeepsBanner() {
    var s = typingInClickedIsland()
    s.apply(.editingEnded, style: .island)
    #expect(s.mode == .signal(.banner))
}
@Test func newSignalEndsTypingAndAppliesPendingCollapse() {
    var s = typingInClickedIsland()
    s.apply(.hoverEnded, style: .island)
    s.apply(.signalRaised, style: .island)
    #expect(!s.isEditing); #expect(s.mode == .signal(.island))
}
@Test func clearedSignalEndsTyping() {
    var s = typingInClickedIsland()
    s.apply(.hoverEnded, style: .island)
    s.apply(.signalCleared, style: .island)
    #expect(!s.isEditing); #expect(s.mode == .idle)
    // Ein späteres Signal startet ohne Tipp-Zustand und klappt wieder normal zu.
    s.apply(.signalRaised, style: .island); s.apply(.islandClicked, style: .island)
    s.apply(.hoverEnded, style: .island)
    #expect(s.mode == .signal(.island))
}
@Test func typingOnlyStartsInASignal() {
    var s = NotchState(); s.apply(.editingBegan, style: .island)
    #expect(!s.isEditing)
    s.apply(.hoverBegan, style: .island); s.apply(.editingBegan, style: .island)
    #expect(!s.isEditing)
}
@Test func settingsAreNotATabAnymore() {
    // Die Einstellungen öffnen sich über die Menüleiste; in der Notch gibt es keinen Knopf mehr dafür.
    #expect(PanelTab.allCases == [.music, .sessions, .office])
}
@Test func openTabOverridesLastTabOnce() {
    var s = NotchState(); s.lastTab = .sessions
    s.openTab = .music
    s.apply(.hoverBegan, style: .island)
    #expect(s.mode == .panel(.music))
    // Der zuletzt gewählte Reiter bleibt, was der Besitzer selbst angeklickt hat.
    #expect(s.lastTab == .sessions)
}
