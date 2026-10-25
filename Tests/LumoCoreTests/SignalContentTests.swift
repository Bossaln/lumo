import Foundation
import Testing
@testable import LumoCore

@Test func doneDismissesItselfAfterFourSeconds() {
    #expect(SignalKind.done.autoDismissDelay == .seconds(4))
    #expect(SignalKind.error.autoDismissDelay == nil)
    #expect(SignalKind.permission.autoDismissDelay == nil)
    #expect(SignalKind.question(options: []).autoDismissDelay == nil)
}
@Test func questionShowsAtMostFourOptions() {
    let kind = SignalKind.question(options: ["A", "B", "C", "D", "E"])
    #expect(kind.visibleOptions == ["A", "B", "C", "D"])
    #expect(SignalKind.permission.visibleOptions.isEmpty)
}
@Test func onlyQuestionsAcceptText() {
    #expect(SignalKind.question(options: ["Ja"]).acceptsText)
    #expect(!SignalKind.permission.acceptsText)
    #expect(!SignalKind.done.acceptsText)
}
@Test func islandPromptPerKind() {
    #expect(SignalKind.permission.islandPrompt == "Erlauben?")
    #expect(SignalKind.question(options: []).islandPrompt == "Frage")
    #expect(SignalKind.done.islandPrompt == "Fertig")
    #expect(SignalKind.error.islandPrompt == "Fehler")
}
@Test func agentNamesAndColors() {
    #expect(SignalAgent.claude.displayName == "Claude")
    #expect(SignalAgent.codex.displayName == "Codex")
    var s = AppSettings.default
    #expect(s.colorHex(for: .claude) == "#E0764A")
    s.codexColorHex = "#112233"
    #expect(s.colorHex(for: .codex) == "#112233")
}
@Test func typedAnswerIsTrimmedAndEmptyIgnored() {
    #expect(SignalAction.typedAnswer("  Blau \n") == .answer("Blau"))
    #expect(SignalAction.typedAnswer("   ") == nil)
}
@Test func onlyPermissionAndQuestionWaitForOwner() {
    // Der Menüleisten-Punkt zeigt nur an, dass etwas auf den Besitzer wartet.
    #expect(SignalKind.permission.isAwaitingOwner)
    #expect(SignalKind.question(options: ["Ja"]).isAwaitingOwner)
    #expect(!SignalKind.done.isAwaitingOwner)
    #expect(!SignalKind.error.isAwaitingOwner)
}
@Test func eachSignalHasItsOwnID() {
    let a = SignalContent(agent: .claude, title: "T", subtitle: "S", kind: .done)
    let b = SignalContent(agent: .claude, title: "T", subtitle: "S", kind: .done)
    #expect(a.id != b.id)
    #expect(a != b)
}
@Test func signalIDCanComeFromTheRequest() {
    // Anfragen tragen die ID der Hook-Anfrage, damit die Entscheidung genau dort ankommt.
    let request = UUID()
    #expect(SignalContent(id: request, agent: .codex, title: "T", subtitle: "S", kind: .permission).id == request)
}
