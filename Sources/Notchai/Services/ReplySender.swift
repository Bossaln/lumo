import AppKit
import ApplicationServices
import NotchaiCore

/// Führt eine `ReplyRoute` aus: Codex bekommt die Antwort über `codex queue`, cmux über `cmux paste`,
/// sonst kommt das Fenster der Session nach vorn und der Text in die Zwischenablage. Automatisch
/// eingetippt wird nur, wenn das Ziel eindeutig ist – eine Antwort landet nie in der falschen Session.
@MainActor
final class ReplySender {
    enum ReplyResult: Equatable {
        case sent, focusedAndCopied, copied
        case failed(String)

        /// Kurzer Hinweis für die Notch.
        var notice: String {
            switch self {
            case .sent: "Gesendet"
            case .focusedAndCopied: "In der Zwischenablage – mit ⌘V einfügen"
            case .copied: "In der Zwischenablage"
            case .failed(let reason): "Nicht gesendet: \(reason)"
            }
        }
    }

    private let home: URL

    init(home: URL) {
        self.home = home
    }

    func send(_ text: String, to session: AgentSession, settings: AppSettings) async -> ReplyResult {
        switch ReplyRouter.route(for: session, settings: settings, messagingSupported: ClaudeMessaging.isSupported) {
        case .codexQueue(let threadId):
            guard let codex = locate("codex", ExecutableLocator.codexCandidates(home: home)) else {
                copy(text)
                return .failed("codex nicht gefunden, Text liegt in der Zwischenablage")
            }
            return await run(codex, ["queue", "--thread", threadId, "--message", text])
        case .cmuxPaste(let surface):
            guard let cmux = locate("cmux", ExecutableLocator.cmuxCandidates) else {
                copy(text)
                return .failed("cmux nicht gefunden, Text liegt in der Zwischenablage")
            }
            return await run(cmux, ["paste", "--surface", surface, "--submit", text])
        case .focusAndClipboard(let bundleId, let autoSend):
            copy(text)
            guard activate(bundleId) else { return .copied }
            guard autoSend else { return .focusedAndCopied }
            // Kurz warten, bis die App wirklich vorn ist, und erst dann prüfen, wohin getippt würde.
            try? await Task.sleep(for: .milliseconds(350))
            guard isSafeToType(into: bundleId, projectName: session.projectName) else { return .focusedAndCopied }
            pasteAndReturn()
            return .sent
        case .claudeMessaging, .clipboardOnly:
            copy(text)
            return .copied
        }
    }

    /// Holt das Fenster der Session nach vorn (Klick auf eine Zeile).
    func focus(_ session: AgentSession) {
        if let bundleId = session.host.bundleId { _ = activate(bundleId) }
    }

    // MARK: - Hilfen

    private func locate(_ name: String, _ candidates: [String]) -> String? {
        ExecutableLocator.find(name, candidates: candidates) { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ executable: String, _ arguments: [String]) async -> ReplyResult {
        let result = await ProcessRunner.run(executable, arguments, environment: await LoginEnvironment.shared.environment(),
                                             timeout: 15)
        if result.status == 0 { return .sent }
        let reason = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(reason.isEmpty ? "Fehlercode \(result.status)" : String(reason.prefix(120)))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func activate(_ bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    /// Nur tippen, wenn Bedienungshilfen erlaubt sind, die Ziel-App vorn ist, ihr Fenster den Projektnamen
    /// trägt und das fokussierte Element ein Terminal ist.
    private func isSafeToType(into bundleId: String, projectName: String) -> Bool {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleId else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        guard let window = element(app, kAXFocusedWindowAttribute),
              let title = string(window, kAXTitleAttribute), title.localizedCaseInsensitiveContains(projectName),
              let focused = element(app, kAXFocusedUIElementAttribute) else { return false }
        let labels = [kAXDescriptionAttribute, kAXTitleAttribute, kAXRoleDescriptionAttribute].compactMap { string(focused, $0) }
        return labels.contains { $0.localizedCaseInsensitiveContains("Terminal") }
    }

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// ⌘V und Return an die vorderste App.
    private func pasteAndReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandV: CGKeyCode = 0x09
        let returnKey: CGKeyCode = 0x24
        for (key, flags) in [(commandV, CGEventFlags.maskCommand), (returnKey, CGEventFlags())] {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
