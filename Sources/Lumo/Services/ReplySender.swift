import AppKit
import ApplicationServices
import LumoCore

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
            case .sent: L("Gesendet")
            case .focusedAndCopied: L("In der Zwischenablage – mit ⌘V einfügen")
            case .copied: L("In der Zwischenablage")
            case .failed(let reason): L("Nicht gesendet: {0}", reason)
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
                return .failed(L("codex nicht gefunden, Text liegt in der Zwischenablage"))
            }
            return await run(codex, ["queue", "--thread", threadId, "--message", text])
        case .cmuxPaste(let surface):
            guard let cmux = locate("cmux", ExecutableLocator.cmuxCandidates) else {
                copy(text)
                return .failed(L("cmux nicht gefunden, Text liegt in der Zwischenablage"))
            }
            // In der Standardeinstellung lässt cmux nur eigene Prozesse an seinen Socket; dann gar nicht erst senden.
            if let mode = await cmuxMode(cmux), !mode.allowsExternalClients {
                return cmuxRefused(text, session: session)
            }
            let result = await run(cmux, ["paste", "--surface", surface, "--submit", text])
            guard case .failed(let reason) = result else { return result }
            if CmuxSocketMode.isAccessDenied(reason) { return cmuxRefused(text, session: session) }
            copy(text)
            return .failed(L("{0}. Text liegt in der Zwischenablage", reason))
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

    /// Holt das Fenster der Session nach vorn (Klick auf eine Zeile, „Fenster öffnen“): in cmux genau ihren Tab,
    /// ein minimiertes Fenster kommt aus dem Dock zurück.
    func focus(_ session: AgentSession) {
        Task {
            await selectCmuxTab(of: session)
            if let bundleId = session.host.bundleId { _ = activate(bundleId) }
        }
    }

    /// cmux wechselt zum Tab und zur Fläche der Session, sofern es lumo lässt (`CmuxSocketMode`).
    private func selectCmuxTab(of session: AgentSession) async {
        guard let workspace = session.host.cmuxWorkspace,
              let cmux = locate("cmux", ExecutableLocator.cmuxCandidates),
              await cmuxMode(cmux)?.allowsExternalClients == true else { return }
        _ = await run(cmux, ["select-workspace", "--workspace", workspace])
        if let surface = session.host.cmuxSurface {
            _ = await run(cmux, ["focus-panel", "--panel", surface, "--workspace", workspace])
        }
    }

    /// Modus des cmux-Sockets; `socket-status` verbindet sich nie mit dem Socket selbst.
    private func cmuxMode(_ cmux: String) async -> CmuxSocketMode? {
        let result = await ProcessRunner.run(cmux, ["socket-status", "--json"],
                                             environment: await LoginEnvironment.shared.environment(), timeout: 5,
                                             includeErrors: false)
        return result.status == 0 ? CmuxSocketMode.parse(statusJSON: result.output) : nil
    }

    /// cmux weist lumo ab: Text in die Zwischenablage, Fenster der Session nach vorn, und sagen, was zu tun ist.
    private func cmuxRefused(_ text: String, session: AgentSession) -> ReplyResult {
        copy(text)
        if let bundleId = session.host.bundleId { _ = activate(bundleId) }
        return .failed(L("cmux lässt lumo nicht senden. Text liegt in der Zwischenablage – in cmux unter Einstellungen › Automatisierung den Automatisierungsmodus wählen"))
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

    /// Holt die App nach vorn. Sind alle ihre Fenster minimiert, kommt das erste zurück: über die Bedienungshilfen,
    /// sonst wie bei einem Klick aufs Dock-Symbol (Reopen).
    private func activate(_ bundleId: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        if !restoreMinimizedWindow(of: app), let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        return app.activate(options: [.activateAllWindows])
    }

    /// `true`, wenn die App ein sichtbares Fenster hat oder eins wiederhergestellt wurde; `false`, wenn das ohne
    /// Bedienungshilfen nicht feststeht.
    private func restoreMinimizedWindow(of app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return false }
        let minimized = windows.filter { isMinimized($0) }
        guard minimized.count == windows.count, let first = minimized.first else { return true }
        return AXUIElementSetAttributeValue(first, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
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
