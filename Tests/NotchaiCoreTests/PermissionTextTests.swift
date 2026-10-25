import Foundation
import Testing
@testable import NotchaiCore

private func input(_ command: String) -> JSONValue {
    .object(["command": .string(command)])
}

@Test func shortCommandHasNoFullVersion() {
    #expect(PermissionText.summary(tool: "Bash", input: input("npm test")) == "npm test")
    #expect(PermissionText.fullCommand(tool: "Bash", input: input("npm test")) == nil)
}

@Test func multiLineCommandKeepsEveryLine() {
    // In der Kurzfassung sähe der Befehl harmlos aus; der ganze muss mitkommen und angekündigt werden.
    let command = "cd ~/projekt\nrm -rf ~/wichtig"
    #expect(PermissionText.summary(tool: "Bash", input: input(command)) == "cd ~/projekt")
    #expect(PermissionText.fullCommand(tool: "Bash", input: input(command)) == command)
    #expect(PermissionText.note(for: command) == "+1 Zeile")
    #expect(PermissionText.note(for: "a\nb\nc") == "+2 Zeilen")
}

@Test func blankFirstLineDoesNotHideTheCommand() {
    #expect(PermissionText.summary(tool: "Bash", input: input("   \nrm -rf ~/wichtig")) == "rm -rf ~/wichtig")
}

@Test func longSingleLineCommandIsAnnounced() {
    let command = "echo " + String(repeating: "x", count: 80) + " && echo ENDE-SICHTBAR"
    #expect(PermissionText.fullCommand(tool: "Bash", input: input(command)) == command)
    #expect(PermissionText.note(for: command) == "ganzer Befehl")
}

@Test func otherToolsKeepTheirDescription() {
    #expect(PermissionText.summary(tool: "WebFetch", input: .object(["url": .string("https://example.com")])) == "https://example.com")
    #expect(PermissionText.fullCommand(tool: "WebFetch", input: .object(["url": .string("https://example.com")])) == nil)
}

@Test func processNeedleStopsAtTheFirstQuote() {
    // Claude Code startet `zsh -c … eval 'echo '\''hi'\'''`; bis zum ersten ' steht der Befehl unverändert da.
    #expect(PermissionText.processNeedle(tool: "Bash", input: input("sleep 30 && echo 'fertig'")) == "sleep 30 && echo")
    #expect(PermissionText.processNeedle(tool: "Bash", input: input("ls '/a'")) == nil)
    #expect(PermissionText.processNeedle(tool: "Write", input: input("sleep 30")) == nil)
}

@Test func startedChildMatchesOnlyNewProcessesWithTheCommand() {
    let args: [Int32: String] = [10: "node mcp-server.js", 11: "/bin/zsh -c source x && eval 'sleep 30 && echo' < /dev/null",
                                 12: "sh -c notchai-hook claude decide"]
    let children: (Int32) -> [Int32] = { _ in [10, 11, 12] }
    #expect(ProcessTree.startedChild(of: 1, containing: "sleep 30 && echo", except: [10, 12],
                                     children: children, arguments: { args[$0] }))
    // Lief derselbe Befehl schon vor der Anfrage (Hintergrund-Shell), zählt er nicht.
    #expect(!ProcessTree.startedChild(of: 1, containing: "sleep 30 && echo", except: [10, 11, 12],
                                      children: children, arguments: { args[$0] }))
}

@Test func procArgsAreParsed() {
    var bytes: [UInt8] = []
    withUnsafeBytes(of: Int32(3)) { bytes += $0 }
    bytes += Array("/bin/zsh".utf8) + [0, 0, 0] + Array("zsh".utf8) + [0] + Array("-c".utf8) + [0] + Array("echo hi".utf8) + [0]
    bytes += Array("HOME=/x".utf8) + [0]
    #expect(ProcessTree.parseProcArgs(bytes) == "zsh -c echo hi")
}

@Test func ownProcessArgumentsAreReadable() {
    #expect(ProcessTree.systemArguments(getpid())?.isEmpty == false)
    #expect(ProcessTree.systemChildren(getppid()).contains(getpid()))
}
