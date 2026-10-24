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
    private static let forwardedKeys: Set<String> = [
        "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_MESSAGING_SOCKET", "TERM_PROGRAM", "__CFBundleIdentifier",
    ]

    /// Größte Antwort, die gelesen wird (eine Entscheidungs-JSON ist wenige hundert Bytes groß).
    private static let replyLimit = 1 << 20

    public static func forwardedEnvironment(_ env: [String: String]) -> [String: String] {
        env.filter { forwardedKeys.contains($0.key) || $0.key.hasPrefix("CMUX_") }
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
