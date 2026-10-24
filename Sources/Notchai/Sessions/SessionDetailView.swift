import Foundation
import NotchaiCore
import SwiftUI

/// Eine Session im Detail (Klick auf ihre Zeile): oben die Zeile selbst mit Anfrage und Antwortfeld, darunter wo sie
/// läuft, Ordner, Modell, Kontext, Nutzungslimits und Verlauf, unten „Fenster öffnen“, „Antworten“ und „Entfernen“.
struct SessionDetailView: View {
    let session: AgentSession
    let now: Date
    let model: AppModel

    private static let labelWidth: CGFloat = 96
    private static let barWidth: CGFloat = 120

    private var settings: AppSettings { model.settingsStore.settings }
    private var agentColor: Color { SessionPalette.agentColor(session.agent, settings: settings) }
    private var theme: SignalTheme { SignalTheme(agentHex: settings.colorHex(for: session.agent)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            backButton
            SessionRowView(session: session, now: now, model: model, isDetail: true)
            VStack(alignment: .leading, spacing: 6) {
                fact(L("Läuft in")) { Text(Self.sourceName(session.host.source)) }
                if let cwd = session.cwd {
                    fact(L("Ordner")) {
                        Text(Self.abbreviatedPath(cwd))
                            .font(SignalTheme.monoFont)
                            .truncationMode(.middle)
                    }
                }
                if let name = session.model {
                    fact(L("Modell")) { Text(name).font(SignalTheme.monoFont) }
                }
                contextFact
                limitFacts
                fact(L("Verlauf")) { Text(historyText) }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            actions
        }
    }

    // MARK: - Teile

    private var backButton: some View {
        Button { model.closeSessionDetail() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text(L("Alle Sessions"))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(SessionPalette.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fact<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(SessionPalette.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            value()
                .foregroundStyle(SessionPalette.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, weight: .medium))
    }

    @ViewBuilder
    private var contextFact: some View {
        if let fraction = session.contextFraction {
            fact(L("Kontext")) {
                HStack(spacing: 8) {
                    ContextBar(fraction: fraction, color: agentColor, width: Self.barWidth)
                    Text(contextText(fraction))
                        .monospacedDigit()
                }
            }
        }
    }

    /// Codex meldet fünf Stunden und eine Woche; Claude Code gibt seine Limits nicht an notchai weiter.
    @ViewBuilder
    private var limitFacts: some View {
        if let limits = session.usageLimits {
            ForEach(Array([limits.primary, limits.secondary].compactMap { $0 }.enumerated()), id: \.offset) { _, window in
                fact(L("Limit {0}", Self.windowName(window.windowMinutes))) {
                    HStack(spacing: 8) {
                        ContextBar(fraction: window.usedPercent / 100, color: agentColor, width: Self.barWidth)
                        Text(limitText(window))
                            .monospacedDigit()
                    }
                }
            }
        } else if session.agent == .claude {
            fact(L("Nutzungslimit")) {
                Text(L("Zeigt nur Claude Code selbst (/usage)"))
                    .foregroundStyle(SessionPalette.secondary)
            }
        } else {
            fact(L("Nutzungslimit")) {
                Text(L("Noch keine Angabe von Codex"))
                    .foregroundStyle(SessionPalette.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            SignalPillButton(title: L("Fenster öffnen"), prominent: true, compact: true, theme: theme) {
                model.onFocusSession?(session)
            }
            SignalPillButton(title: model.replyTargetID == session.id ? L("Antwort schließen") : L("Antworten"),
                             compact: true, theme: theme) {
                model.replyTargetID = model.replyTargetID == session.id ? nil : session.id
            }
            Spacer(minLength: 8)
            Button { model.dismissSession(session) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle")
                    Text(L("Aus der Notch entfernen"))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SessionPalette.barAlarm)
                .padding(.horizontal, 11)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(SessionPalette.barAlarm.opacity(0.12)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("Kommt zurück, sobald die Session wieder etwas tut"))
        }
    }

    // MARK: - Texte

    private func contextText(_ fraction: Double) -> String {
        guard let tokens = session.contextTokens, let limit = session.contextLimit else { return contextPercent(fraction) }
        return L("{0} · {1} von {2} Tokens", contextPercent(fraction), Self.tokens(tokens), Self.tokens(limit))
    }

    private func limitText(_ window: UsageWindow) -> String {
        let used = "\(Int(window.usedPercent.rounded()))%"
        guard let reset = window.resetsAt else { return used }
        let seconds = Int(reset.timeIntervalSince(now))
        let when: String = switch seconds {
        case ..<60: L("gleich wieder frei")
        case ..<3600: L("frei in {0} min", seconds / 60)
        case ..<86_400: L("frei in {0} h {1} min", seconds / 3600, seconds % 3600 / 60)
        default: L("frei ab {0}", reset.formatted(Date.FormatStyle(locale: Locale(identifier: Localization.language.rawValue))
            .weekday(.abbreviated).hour().minute()))
        }
        return used + " · " + when
    }

    private var historyText: String {
        var parts: [String] = []
        if let started = session.startedAt { parts.append(L("gestartet {0}", RelativeTime.short(from: started, now: now))) }
        parts.append(session.promptCount == 1 ? L("1 Prompt") : L("{0} Prompts", session.promptCount))
        parts.append(session.editedFileCount == 1 ? L("1 Datei geändert") : L("{0} Dateien geändert", session.editedFileCount))
        if session.errorCount > 0 { parts.append(L("{0} Fehler", session.errorCount)) }
        return parts.joined(separator: " · ")
    }

    static func sourceName(_ source: SessionSource) -> String {
        switch source {
        case .terminal(let name): name ?? L("Terminal")
        case .claudeApp: L("Claude-App")
        case .codexApp: L("Codex-App")
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .cmux: "cmux"
        case .exec: L("Ohne Fenster (codex exec)")
        case .sdk: "Agent SDK"
        case .unknown: L("Unbekannt")
        }
    }

    /// 300 → „5 Std.“, 10 080 → „Woche“.
    static func windowName(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        if minutes == 10_080 { return L("Woche") }
        if minutes % 1440 == 0 { return L("{0} Tage", minutes / 1440) }
        if minutes % 60 == 0 { return L("{0} Std.", minutes / 60) }
        return L("{0} Min.", minutes)
    }

    /// 84 000 → „84k“, 1 000 000 → „1M“.
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = (Double(count) / 100_000).rounded() / 10
            return millions == millions.rounded() ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        if count >= 1000 { return "\(Int((Double(count) / 1000).rounded()))k" }
        return "\(count)"
    }

    static func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
