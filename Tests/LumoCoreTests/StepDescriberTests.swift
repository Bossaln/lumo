import Foundation
import Testing
@testable import LumoCore

private func describe(_ tool: String, _ input: String?) throws -> String {
    let value = try input.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    return StepDescriber.describe(tool: tool, input: value)
}

@Test func shellCommandsShowTheFirstLine() throws {
    #expect(try describe("Bash", #"{"command":"swift test\necho fertig"}"#) == "Führt aus: swift test")
    #expect(try describe("exec_command", #"{"cmd":"ls -la"}"#) == "Führt aus: ls -la")
    // Codex' altes `shell` bekommt ein Array; bei `bash -lc` zählt das eigentliche Kommando.
    #expect(try describe("shell", #"{"command":["bash","-lc","git status"]}"#) == "Führt aus: git status")
    #expect(try describe("shell", #"{"command":["rg","notch"]}"#) == "Führt aus: rg notch")
}

@Test func fileToolsShowTheFileName() throws {
    #expect(try describe("Edit", #"{"file_path":"/a/b/NotchShape.swift"}"#) == "Bearbeitet NotchShape.swift")
    #expect(try describe("MultiEdit", #"{"file_path":"/a/b/c.swift"}"#) == "Bearbeitet c.swift")
    #expect(try describe("Write", #"{"file_path":"/a/neu.md"}"#) == "Schreibt neu.md")
    #expect(try describe("Read", #"{"file_path":"/a/README.md"}"#) == "Liest README.md")
    #expect(try describe("NotebookEdit", #"{"notebook_path":"/a/n.ipynb"}"#) == "Bearbeitet n.ipynb")
}

@Test func applyPatchNamesTheFirstFile() throws {
    let patch = "*** Begin Patch\n*** Update File: Sources/App/Main.swift\n@@\n-a\n+b\n*** End Patch"
    #expect(StepDescriber.describe(tool: "apply_patch", input: .string(patch)) == "Bearbeitet Main.swift")
    #expect(StepDescriber.describe(tool: "apply_patch", input: .object(["input": .string(patch)])) == "Bearbeitet Main.swift")
}

@Test func otherToolsHaveShortGermanNames() throws {
    #expect(try describe("Grep", #"{"pattern":"NotchState"}"#) == "Sucht NotchState")
    #expect(try describe("Glob", #"{"pattern":"**/*.swift"}"#) == "Sucht **/*.swift")
    #expect(try describe("WebFetch", #"{"url":"https://x"}"#) == "Recherchiert im Web")
    #expect(try describe("WebSearch", nil) == "Recherchiert im Web")
    #expect(try describe("AskUserQuestion", nil) == "Fragt dich")
    #expect(try describe("Task", nil) == "Startet Unteragent")
    #expect(try describe("Agent", nil) == "Startet Unteragent")
    #expect(try describe("TodoWrite", nil) == "Plant")
    #expect(try describe("update_plan", nil) == "Plant")
    #expect(try describe("mcp__github__create_issue", nil) == "mcp__github__create_issue")
}

@Test func longStepsAreCutAtSixtyCharacters() throws {
    let long = String(repeating: "x", count: 100)
    let step = try describe("Bash", #"{"command":"\#(long)"}"#)
    #expect(step == "Führt aus: " + String(repeating: "x", count: 60) + "…")
    #expect(try describe("Bash", #"{"command":""}"#) == "Führt einen Befehl aus")
}
