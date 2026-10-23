import Foundation
import Testing
@testable import NotchaiCore

private func parse(_ s: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))
}

@Test func allowOutputIsExact() throws {
    let o = try parse(HookOutput.permissionAllow())
    #expect(o["hookSpecificOutput"]?["hookEventName"]?.stringValue == "PermissionRequest")
    #expect(o["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue == "allow")
}

@Test func denyOutputCarriesMessage() throws {
    let o = try parse(HookOutput.permissionDeny(message: "Abgelehnt in notchai"))
    #expect(o["hookSpecificOutput"]?["decision"]?["behavior"]?.stringValue == "deny")
    #expect(o["hookSpecificOutput"]?["decision"]?["message"]?.stringValue == "Abgelehnt in notchai")
}

@Test func outputsAreSingleLines() {
    // Die Agenten lesen stdout als ein JSON-Dokument; ein Zeilenumbruch darin wäre harmlos, aber unnötig.
    #expect(!HookOutput.permissionAllow().contains("\n"))
    #expect(!HookOutput.permissionDeny(message: "a\nb").contains("\n"))
    #expect(HookOutput.noDecision == "")
}

/// Form aus `docs/hooks.md`, Abschnitt 2: die unveränderte Eingabe plus `answers` (Fragetext → Antwort).
@Test func questionAnswerMatchesExploredShape() throws {
    let input = try parse(#"""
    {"questions":[{"question":"Welche Farbe?","header":"Farbe","options":[{"label":"Rot","description":"warm"},{"label":"Blau","description":"kalt"}],"multiSelect":false}]}
    """#)
    let o = try parse(HookOutput.questionAnswer(toolInput: input, answers: ["Welche Farbe?": "Blau"]))
    let specific = try #require(o["hookSpecificOutput"])
    #expect(specific["hookEventName"]?.stringValue == "PreToolUse")
    #expect(specific["permissionDecision"]?.stringValue == "allow")
    #expect(specific["updatedInput"]?["questions"] == input["questions"])
    #expect(specific["updatedInput"]?["answers"] == .object(["Welche Farbe?": .string("Blau")]))
}

@Test func questionAnswerKeepsOtherInputFields() throws {
    // `updatedInput` ersetzt die ganze Eingabe; was der Agent sonst mitschickt, muss mit zurück.
    let input = try parse(#"{"questions":[],"metadata":{"source":"remember"}}"#)
    let o = try parse(HookOutput.questionAnswer(toolInput: input, answers: [:]))
    #expect(o["hookSpecificOutput"]?["updatedInput"]?["metadata"]?["source"]?.stringValue == "remember")
}
