import Foundation
import Testing
@testable import LumoCore

private func session(_ agent: AgentKind = .claude, host: SessionHost) -> AgentSession {
    AgentSession(id: "\(agent.rawValue):s1", agent: agent, sessionId: "s1", title: "t", projectName: "lumo",
                 cwd: "/p/lumo", status: .ready, lastStep: nil, errorCount: 0, contextFraction: nil,
                 lastActivity: Date(), pending: nil, host: host)
}

@Test func codexAlwaysQueues() {
    let s = session(.codex, host: SessionHost(cmuxSurface: "surface:1", originator: "codex_tui"))
    #expect(ReplyRouter.route(for: s, settings: .default, messagingSupported: true) == .codexQueue(threadId: "s1"))
}

@Test func messagingWinsWhenSupported() {
    let s = session(host: SessionHost(bundleId: "com.apple.Terminal", cmuxSurface: "surface:1", messagingSocket: "/tmp/cc.sock"))
    #expect(ReplyRouter.route(for: s, settings: .default, messagingSupported: true) == .claudeMessaging(socketPath: "/tmp/cc.sock"))
    // Laut Erkundung taugt der Socket nicht für Antworten; dann geht cmux vor.
    #expect(ClaudeMessaging.isSupported == false)
    #expect(ReplyRouter.route(for: s, settings: .default, messagingSupported: ClaudeMessaging.isSupported) == .cmuxPaste(surface: "surface:1"))
}

@Test func cmuxBeforeFocus() {
    let s = session(host: SessionHost(bundleId: "com.cmuxterm.app", cmuxSurface: "surface:4"))
    #expect(ReplyRouter.route(for: s, settings: .default, messagingSupported: false) == .cmuxPaste(surface: "surface:4"))
}

@Test func desktopNeverAutoSends() {
    var settings = AppSettings.default
    settings.autoSendClaudeReplies = true
    let s = session(host: SessionHost(entrypoint: "claude-desktop", bundleId: "com.anthropic.claudefordesktop"))
    #expect(ReplyRouter.route(for: s, settings: settings, messagingSupported: false)
            == .focusAndClipboard(bundleId: "com.anthropic.claudefordesktop", autoSend: false))
}

@Test func vscodeAutoSendFollowsSetting() {
    var settings = AppSettings.default
    let s = session(host: SessionHost(entrypoint: "cli", bundleId: "com.microsoft.VSCode", termProgram: "vscode"))
    #expect(ReplyRouter.route(for: s, settings: settings, messagingSupported: false)
            == .focusAndClipboard(bundleId: "com.microsoft.VSCode", autoSend: false))
    settings.autoSendClaudeReplies = true
    #expect(ReplyRouter.route(for: s, settings: settings, messagingSupported: false)
            == .focusAndClipboard(bundleId: "com.microsoft.VSCode", autoSend: true))
}

@Test func unknownHostIsClipboardOnly() {
    #expect(ReplyRouter.route(for: session(host: SessionHost()), settings: .default, messagingSupported: false) == .clipboardOnly)
}

@Test func locatorPicksFirstExisting() {
    let existing: Set<String> = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    #expect(ExecutableLocator.find("codex", candidates: ["/Users/x/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"],
                                   fileExists: existing.contains) == "/opt/homebrew/bin/codex")
    #expect(ExecutableLocator.find("codex", candidates: ["/nirgends/codex"], fileExists: existing.contains) == nil)
    let home = URL(filePath: "/Users/x")
    #expect(ExecutableLocator.codexCandidates(home: home).first == "/Users/x/.local/bin/codex")
    #expect(ExecutableLocator.cmuxCandidates == ["/Applications/cmux.app/Contents/Resources/bin/cmux"])
}
