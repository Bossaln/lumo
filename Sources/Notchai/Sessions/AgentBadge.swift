import NotchaiCore
import SwiftUI

/// Kleines Agentenzeichen in der Unterzeile: Claude als 12×9-Pixel-Figur, Codex als Terminal-Symbol,
/// beide in der eingestellten Agentenfarbe.
struct AgentBadge: View {
    let agent: AgentKind
    let color: Color

    var body: some View {
        switch agent {
        case .claude:
            PixelCreature(color: color)
        case .codex:
            Image(systemName: "apple.terminal")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12, height: 9)
        }
    }
}

/// Kleine Pixel-Figur, im Code gezeichnet.
struct PixelCreature: View {
    let color: Color

    /// `#` Körper, `e` Auge, `.` leer.
    private static let rows = [
        "..########..",
        ".##########.",
        ".##e####e##.",
        "###e####e###",
        "############",
        "#.########.#",
        "..########..",
        "..#.#..#.#..",
        "..#.#..#.#..",
    ]

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width / 12, size.height / 9)
            for (y, row) in Self.rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel != "." {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(pixel == "e" ? .black : color))
                }
            }
        }
        .frame(width: 12, height: 9)
    }
}

/// Farben und Texte der Session-Ansichten.
enum SessionPalette {
    static let title = Color.white
    /// #8E8E93
    static let secondary = Color(hex: "#8E8E93")
    /// #6E6E73
    static let footer = Color(hex: "#6E6E73")
    static let barTrack = Color(hex: "#3A3A3C")
    static let barAlarm = Color(hex: "#FF5A4F")
    static let working = Color(hex: "#2A6A99")
    static let finished = Color(hex: "#2D7A4A")

    static func agentColor(_ agent: AgentKind, settings: AppSettings) -> Color {
        Color(hex: settings.colorHex(for: agent))
    }

    /// „Claude Code“ bzw. „Codex“ in der Unterzeile.
    static func agentName(_ agent: AgentKind) -> String {
        agent == .claude ? "Claude Code" : "Codex"
    }

    static func statusText(_ session: AgentSession) -> String {
        switch session.status {
        case .working: session.lastStep ?? "Arbeitet"
        case .waitingApproval: "Wartet auf Freigabe"
        case .waitingAnswer: "Wartet auf dich"
        case .done: session.lastStep ?? "Fertig"
        case .ready: "Bereit"
        case .error: session.lastStep ?? "Fehler"
        }
    }
}
