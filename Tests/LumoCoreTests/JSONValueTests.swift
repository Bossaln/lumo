import Foundation
import Testing
@testable import LumoCore

@Test func decodesClaudePermissionRequest() throws {
    let json = #"{"session_id":"s1","hook_event_name":"PermissionRequest","cwd":"/p","tool_name":"Bash","tool_input":{"command":"npm install"},"extra":1}"#
    let e = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(e.sessionId == "s1"); #expect(e.toolName == "Bash")
    #expect(e.toolInput?["command"]?.stringValue == "npm install")
}

@Test func wronglyTypedOptionalFieldDoesNotSpoilTheEvent() throws {
    // Ein Agent schickt ein Feld in anderer Form als erwartet: nur dieses Feld fehlt dann.
    let json = #"{"session_id":"s1","hook_event_name":"StopFailure","error":{"type":"rate_limit"},"cwd":"/p"}"#
    let e = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    #expect(e.hookEventName == "StopFailure")
    #expect(e.error == nil)
    #expect(e.cwd == "/p")
}

@Test func eventWithoutSessionIdIsRejected() {
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(HookEvent.self, from: Data(#"{"hook_event_name":"Stop"}"#.utf8))
    }
}

@Test func jsonValueRoundTripKeepsEveryKind() throws {
    let json = #"{"a":null,"b":true,"c":130,"d":"x/y","e":[1,"zwei"],"f":{"g":false}}"#
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    #expect(v["a"] == .null)
    #expect(v["b"] == .bool(true))
    #expect(v["c"] == .number(130))
    #expect(v["e"] == .array([.number(1), .string("zwei")]))
    #expect(v["f"]?["g"] == .bool(false))
    let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
    #expect(again == v)
}

@Test func wireRoundTripIsSingleLine() throws {
    let r = HookReply(requestId: UUID(), stdout: "{\"a\":1}")
    let line = try HookWire.encodeLine(r)
    #expect(line.last == UInt8(ascii: "\n")); #expect(!line.dropLast().contains(UInt8(ascii: "\n")))
    #expect(try HookWire.decodeLine(line, as: HookReply.self) == r)
}

@Test func envelopeSurvivesTheWire() throws {
    let event = try JSONDecoder().decode(HookEvent.self, from: Data(
        #"{"session_id":"s1","hook_event_name":"Stop","last_assistant_message":"Zeile 1\nZeile 2"}"#.utf8))
    let sent = HookEnvelope(requestId: UUID(), agent: .codex, mode: .event, event: event,
                            env: ["TERM_PROGRAM": "vscode"], sentAt: Date(timeIntervalSince1970: 1_792_683_988))
    let back = try HookWire.decodeLine(HookWire.encodeLine(sent), as: HookEnvelope.self)
    #expect(back.requestId == sent.requestId)
    #expect(back.agent == .codex)
    #expect(back.mode == .event)
    #expect(back.event == event)
    #expect(back.env == ["TERM_PROGRAM": "vscode"])
    #expect(back.sentAt == sent.sentAt)
}

@Test func socketPathHonoursOverride() {
    let home = URL(filePath: "/Users/x")
    #expect(LumoPaths.socketPath(home: home, env: [:]) == "/Users/x/Library/Application Support/lumo/lumo.sock")
    #expect(LumoPaths.socketPath(home: home, env: ["LUMO_SOCKET": "/tmp/t.sock"]) == "/tmp/t.sock")
}

@Test func installPathsLiveInApplicationSupport() {
    let home = URL(filePath: "/Users/x")
    #expect(LumoPaths.hookBinary(home: home).path == "/Users/x/Library/Application Support/lumo/bin/lumo-hook")
    #expect(LumoPaths.backupsDir(home: home).path == "/Users/x/Library/Application Support/lumo/backups")
}
