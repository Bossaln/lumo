import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Logik von `notchai-hook`: Ereignis lesen, an die App schicken und bei `decide` auf die Entscheidung
/// warten. Jeder Fehler endet in „keine Ausgabe“, damit der Agent wie ohne notchai weiterarbeitet.
public enum HookClient {
    /// Umgebungsvariablen, aus denen die App erkennt, wo eine Session läuft (`SessionHost`).
    /// Das Messaging-Token bleibt draußen: notchai nutzt den Nachrichten-Socket nicht (`docs/hooks.md`).
    /// Von cmux nur die IDs der Fläche und des Tabs; cmux setzt daneben Zugangsdaten für seinen Socket
    /// (`CMUX_CUA_SOCKET_AUTH_TOKEN`, `CMUX_SOCKET_CAPABILITY` …), die notchai nichts angehen.
    private static let forwardedKeys: Set<String> = [
        "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_MESSAGING_SOCKET", "TERM_PROGRAM", "__CFBundleIdentifier",
        "CMUX_SURFACE_ID", "CMUX_PANEL_ID", "CMUX_WORKSPACE_ID", "CMUX_TAB_ID",
    ]

    /// Größte Antwort, die gelesen wird (eine Entscheidungs-JSON ist wenige hundert Bytes groß).
    private static let replyLimit = 1 << 20

    public static func forwardedEnvironment(_ env: [String: String]) -> [String: String] {
        env.filter { forwardedKeys.contains($0.key) || isSurfaceKey($0.key) }
    }

    /// Ältere cmux-Versionen nennen die Fläche anders; jede `CMUX_…SURFACE…_ID` zählt, solange der Name nicht
    /// nach Zugangsdaten klingt.
    private static func isSurfaceKey(_ key: String) -> Bool {
        key.hasPrefix("CMUX_") && key.contains("SURFACE") && key.hasSuffix("_ID") && !HookExport.isSecretName(key)
    }

    /// Aufruf als `notchai-hook <claude|codex> <event|decide>`; gibt den Text für stdout zurück (meist leer).
    /// `agentPid`: Prozess des Agenten, der den Hook gestartet hat (`ProcessTree.agent`).
    public static func run(arguments: [String], stdin: Data, env: [String: String], home: URL, agentPid: Int32? = nil,
                           connectTimeout: TimeInterval = 0.3, decisionTimeout: TimeInterval = 125) -> String {
        guard arguments.count == 2,
              let agent = AgentKind(rawValue: arguments[0]),
              let mode = HookMode(rawValue: arguments[1]),
              let event = try? JSONDecoder().decode(HookEvent.self, from: stdin) else { return HookOutput.noDecision }
        let envelope = HookEnvelope(requestId: UUID(), agent: agent, mode: mode, event: event,
                                    env: forwardedEnvironment(env), sentAt: Date(), agentPid: agentPid)
        guard let line = try? HookWire.encodeLine(envelope),
              let fd = UnixSocket.openClient(path: NotchaiPaths.socketPath(home: home, env: env),
                                             timeout: connectTimeout) else { return HookOutput.noDecision }
        defer { close(fd) }
        // Die App liest sofort; eine Sekunde reicht auch für große Werkzeug-Eingaben.
        guard UnixSocket.sendAll(fd, line, timeout: max(connectTimeout, 1)), mode == .decide,
              let answer = UnixSocket.readLine(fd, timeout: decisionTimeout, limit: replyLimit),
              let reply = try? HookWire.decodeLine(answer, as: HookReply.self),
              reply.requestId == envelope.requestId else { return HookOutput.noDecision }
        return reply.stdout
    }
}
