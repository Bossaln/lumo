import Foundation
import Testing
@testable import LumoCore

@Test func cmuxCredentialsAreNeverForwarded() {
    let env = HookClient.forwardedEnvironment([
        "CMUX_SURFACE_ID": "s1", "CMUX_PANEL_ID": "s1", "CMUX_WORKSPACE_ID": "w1", "CMUX_TAB_ID": "w1",
        "CMUX_CUA_SOCKET_AUTH_TOKEN": "geheim", "CMUX_SOCKET_CAPABILITY": "geheim", "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
        "CMUX_CUA_AUTH_TOKEN_FILE": "/tmp/token", "CMUX_OLD_SURFACE_ID": "s0",
    ])
    #expect(env == ["CMUX_SURFACE_ID": "s1", "CMUX_PANEL_ID": "s1", "CMUX_WORKSPACE_ID": "w1", "CMUX_TAB_ID": "w1",
                    "CMUX_OLD_SURFACE_ID": "s0"])
}

@Test func exportRedactsSecretsAndShortensContents() {
    var event = HookEvent(hookEventName: "PreToolUse", sessionId: "s1")
    event.prompt = String(repeating: "p", count: 500)
    event.toolInput = .object(["content": .string(String(repeating: "c", count: 300)), "count": .number(3)])
    let envelope = HookEnvelope(requestId: UUID(), agent: .claude, mode: .event, event: event,
                                env: ["CMUX_SURFACE_ID": "s1", "OLD_AUTH_TOKEN": "geheim"], sentAt: Date())
    let copy = HookExport.redacted(envelope)
    #expect(copy.env == ["CMUX_SURFACE_ID": "s1", "OLD_AUTH_TOKEN": "‹entfernt›"])
    #expect(copy.event.prompt == String(repeating: "p", count: 80) + "… (500 Zeichen)")
    #expect(copy.event.toolInput?["content"]?.stringValue?.hasSuffix("… (300 Zeichen)") == true)
    #expect(copy.event.toolInput?["count"] == .number(3))
    #expect(copy.event.hookEventName == "PreToolUse")
}

@Test func modelIdsBecomeReadable() {
    #expect(ModelName.display("claude-opus-5-5") == "Opus 5.5")
    #expect(ModelName.display("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    #expect(ModelName.display("claude-haiku-5") == "Haiku 5")
    #expect(ModelName.display("gpt-5.4-codex") == "gpt-5.4-codex")
    #expect(ModelName.display("claude-opus") == "claude-opus")
}

@Test func cmuxSocketModeIsRead() {
    let status = #"{"configured_mode":"cmuxOnly","effective_mode":"cmuxOnly","socket_path":"/x"}"#
    #expect(CmuxSocketMode.parse(statusJSON: status) == .cmuxOnly)
    #expect(CmuxSocketMode.cmuxOnly.allowsExternalClients == false)
    #expect(CmuxSocketMode.parse(statusJSON: #"{"effective_mode":"automation"}"#)?.allowsExternalClients == true)
    #expect(CmuxSocketMode.parse(statusJSON: "kein json") == nil)
    #expect(CmuxSocketMode.isAccessDenied("Error: failed to write to socket (Broken pipe, errno 32)"))
    #expect(CmuxSocketMode.isAccessDenied("ERROR: Zugriff verweigert – nur innerhalb von cmux gestartete Prozesse"))
    #expect(!CmuxSocketMode.isAccessDenied("surface not found"))
}
