import Testing
@testable import NotchaiCore

@Test func setupWalksThroughAllStepsInOrder() {
    var step = SetupStep.welcome
    var visited = [step]
    while let next = step.next {
        step = next
        visited.append(step)
    }
    #expect(visited == SetupStep.allCases)
    #expect(visited.first == .welcome)
    #expect(visited.last == .done)
}

@Test func setupCanGoBackButNotBeforeTheStart() {
    #expect(SetupStep.welcome.previous == nil)
    #expect(SetupStep.claude.previous == .welcome)
    #expect(SetupStep.done.next == nil)
}

@Test func setupProgressRunsFromZeroToOne() {
    #expect(SetupStep.welcome.progress == 0)
    #expect(SetupStep.done.progress == 1)
    let all = SetupStep.allCases.map(\.progress)
    #expect(all == all.sorted())
}
