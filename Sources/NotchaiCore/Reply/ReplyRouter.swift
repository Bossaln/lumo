/// Kann notchai Text über `CLAUDE_CODE_MESSAGING_SOCKET` als Antwort in eine Claude-Session schicken?
/// Nein: Dort kommt er als Nachricht einer anderen Session an, nicht als Eingabe des Besitzers
/// (`docs/hooks.md`, Abschnitt 3).
public enum ClaudeMessaging {
    public static let isSupported = false
}

/// Wie eine Antwort aus der Notch zu ihrer Session kommt.
public enum ReplyRoute: Equatable, Sendable {
    /// `codex queue --thread <id> --message <text>`
    case codexQueue(threadId: String)
    case claudeMessaging(socketPath: String)
    /// `cmux paste --surface <id> --submit <text>`
    case cmuxPaste(surface: String)
    /// Fenster der Host-App nach vorn, Text in die Zwischenablage; bei `autoSend` zusätzlich einfügen
    /// und abschicken, aber nur, wenn das richtige Fenster sicher erkannt ist.
    case focusAndClipboard(bundleId: String, autoSend: Bool)
    case clipboardOnly
}

public enum ReplyRouter {
    /// In der Claude-App lässt sich der richtige Chat nicht prüfen; dorthin wird nie automatisch getippt.
    public static let claudeDesktopBundleId = "com.anthropic.claudefordesktop"

    public static func route(for session: AgentSession, settings: AppSettings, messagingSupported: Bool) -> ReplyRoute {
        if session.agent == .codex { return .codexQueue(threadId: session.sessionId) }
        let host = session.host
        if messagingSupported, let socket = host.messagingSocket { return .claudeMessaging(socketPath: socket) }
        if let surface = host.cmuxSurface { return .cmuxPaste(surface: surface) }
        if let bundleId = host.bundleId {
            return .focusAndClipboard(bundleId: bundleId,
                                      autoSend: settings.autoSendClaudeReplies && bundleId != claudeDesktopBundleId)
        }
        return .clipboardOnly
    }
}
