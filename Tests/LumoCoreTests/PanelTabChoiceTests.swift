import Testing
@testable import LumoCore

private func choose(_ behavior: PanelOpenBehavior = .activity, last: PanelTab = .office, waiting: Bool = false,
                    music: Bool = false, running: Bool = false) -> PanelTab {
    PanelTabChoice.tab(behavior: behavior, lastTab: last,
                       activity: NotchActivity(ownerAwaited: waiting, musicPlaying: music, sessionsRunning: running))
}

@Test func playingMusicOpensMusic() {
    #expect(choose(music: true) == .music)
    // Musik geht arbeitenden Agenten vor.
    #expect(choose(music: true, running: true) == .music)
}

@Test func requestFromAgentBeatsMusic() {
    #expect(choose(waiting: true, music: true) == .sessions)
}

@Test func runningSessionsOpenSessions() {
    #expect(choose(running: true) == .sessions)
}

@Test func nothingHappeningOpensLastTab() {
    #expect(choose(last: .office) == .office)
}

@Test func lastUsedIgnoresActivity() {
    #expect(choose(.lastUsed, last: .office, waiting: true, music: true) == .office)
}
