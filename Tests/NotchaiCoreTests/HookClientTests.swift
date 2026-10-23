import Foundation
import Testing
@testable import NotchaiCore

@Test func noAppMeansNoOutput() {
    let out = HookClient.run(arguments: ["claude", "decide"], stdin: Data(#"{"session_id":"s","hook_event_name":"PermissionRequest"}"#.utf8),
                             env: ["NOTCHAI_SOCKET": "/tmp/notchai-missing-\(UUID()).sock"], home: URL(filePath: "/tmp"))
    #expect(out == "")
}

@Test func garbageStdinMeansNoOutput() {
    #expect(HookClient.run(arguments: ["claude", "event"], stdin: Data("kein json".utf8), env: [:], home: URL(filePath: "/tmp")) == "")
}

@Test func unknownArgumentsMeanNoOutput() {
    #expect(HookClient.run(arguments: ["gemini"], stdin: Data("{}".utf8), env: [:], home: URL(filePath: "/tmp")) == "")
    #expect(HookClient.run(arguments: ["claude", "wait"], stdin: Data("{}".utf8), env: [:], home: URL(filePath: "/tmp")) == "")
}

@Test func onlyWhitelistedEnvIsForwarded() {
    let env = HookClient.forwardedEnvironment(["CMUX_SURFACE_ID": "s:1", "HOME": "/x", "TERM_PROGRAM": "vscode", "SECRET": "y",
                                               "CLAUDE_CODE_MESSAGING_TOKEN": "geheim"])
    #expect(env == ["CMUX_SURFACE_ID": "s:1", "TERM_PROGRAM": "vscode"])
}

@Test func tooLongSocketPathMeansNoOutput() {
    // Unix-Socket-Pfade sind auf etwa 104 Bytes begrenzt; ein zu langer Pfad darf nichts kaputtmachen.
    let long = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    #expect(HookClient.run(arguments: ["claude", "event"], stdin: Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8),
                           env: ["NOTCHAI_SOCKET": long], home: URL(filePath: "/tmp")) == "")
}
