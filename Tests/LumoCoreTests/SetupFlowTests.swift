import Testing
@testable import LumoCore

@Test func setupWalksThroughAllStepsInOrder() {
    var step = SetupStep.language
    var visited = [step]
    while let next = step.next {
        step = next
        visited.append(step)
    }
    #expect(visited == SetupStep.allCases)
    // Zuerst die Sprache, damit alles Weitere schon in ihr erscheint.
    #expect(visited.first == .language)
    #expect(visited[1] == .welcome)
    #expect(visited.last == .done)
}

@Test func setupCanGoBackButNotBeforeTheStart() {
    #expect(SetupStep.language.previous == nil)
    #expect(SetupStep.welcome.previous == .language)
    #expect(SetupStep.claude.previous == .welcome)
    #expect(SetupStep.done.next == nil)
}

@Test func setupProgressRunsFromZeroToOne() {
    #expect(SetupStep.language.progress == 0)
    #expect(SetupStep.done.progress == 1)
    let all = SetupStep.allCases.map(\.progress)
    #expect(all == all.sorted())
}
