import NotchaiCore
import SwiftUI

/// Eine Session: Punkt, fetter Titel, Unterzeile mit Projekt · Agent · Schritt, rechts
/// Gedächtnis-Balken und Zeit. Eine wartende Zeile ist hervorgehoben und trägt ihre Knöpfe selbst.
struct SessionRowView: View {
    let session: AgentSession
    let now: Date
    let model: AppModel
    /// Detailkarte der Kreise: Antwortfeld immer offen.
    var alwaysShowsReply = false

    @ViewState private var hovering = false

    private var settings: AppSettings { model.settingsStore.settings }
    private var agentColor: Color { SessionPalette.agentColor(session.agent, settings: settings) }
    private var theme: SignalTheme { SignalTheme(agentHex: settings.colorHex(for: session.agent)) }
    private var isReplying: Bool { alwaysShowsReply || model.replyTargetID == session.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                statusDot
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(SessionPalette.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    subline
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .contentShape(Rectangle())
            // Klick auf die Zeile holt das Fenster der Session nach vorn (nicht auf Knöpfe und Antwortfeld darunter).
            .onTapGesture { model.onFocusSession?(session) }
            if let pending = session.pending {
                pendingButtons(pending)
                    .padding(.leading, 22)
            }
            if isReplying {
                replyField
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(background)
        .onHover { hovering = $0 }
    }

    // MARK: - Teile

    /// Gefüllt, solange etwas passiert oder wartet; ein Ring, wenn die Session bereit ist.
    @ViewBuilder
    private var statusDot: some View {
        if session.status == .ready {
            Circle().strokeBorder(agentColor, lineWidth: 1.5).frame(width: 7, height: 7)
        } else {
            Circle().fill(session.status == .error ? SignalTheme.red : agentColor).frame(width: 7, height: 7)
        }
    }

    private var subline: some View {
        HStack(spacing: 4) {
            Text(session.projectName)
                .lineLimit(1)
                .layoutPriority(1)
            Text("·")
            AgentBadge(agent: session.agent, color: agentColor)
            Text(SessionPalette.agentName(session.agent))
                .foregroundStyle(agentColor)
                .fixedSize()
            Text("· " + SessionPalette.statusText(session))
                .lineLimit(1)
                .truncationMode(.tail)
            if session.errorCount > 0 {
                Text("· \(session.errorCount) Fehler")
                    .fixedSize()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(SessionPalette.secondary)
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            if (hovering || isReplying) && !alwaysShowsReply {
                Button {
                    model.replyTargetID = isReplying ? nil : session.id
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isReplying ? Color.white : SessionPalette.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(SignalTheme.buttonFill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Antworten")
            }
            if let fraction = session.contextFraction {
                ContextBar(fraction: fraction, color: agentColor)
                Text(contextPercent(fraction))
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            Text(RelativeTime.short(from: session.lastActivity, now: now))
                .frame(minWidth: 58, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(SessionPalette.secondary)
        .fixedSize()
    }

    @ViewBuilder
    private var background: some View {
        if session.status.isWaiting {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(agentColor.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(agentColor.opacity(0.45), lineWidth: 1))
        } else if hovering {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05))
        }
    }

    /// Freigabe: Ablehnen/Erlauben. Frage: bis zu vier Optionen und „Im Terminal antworten“.
    @ViewBuilder
    private func pendingButtons(_ pending: PendingRequest) -> some View {
        let id = pending.requestId
        HStack(spacing: 6) {
            switch pending.kind {
            case .permission(_, let summary):
                Text(summary)
                    .font(SignalTheme.monoFont)
                    .foregroundStyle(theme.detailColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SignalPillButton(title: "Ablehnen", compact: true, theme: theme) { model.onDecide?(id, .deny) }
                SignalPillButton(title: "Erlauben", prominent: true, compact: true, theme: theme) { model.onDecide?(id, .allow) }
            case .question(let question):
                Text(question.question)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SessionPalette.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(question.options.prefix(4)), id: \.self) { option in
                    SignalPillButton(title: option, compact: true, theme: theme) { model.onDecide?(id, .answer(option)) }
                }
                SignalPillButton(title: "Im Terminal antworten", compact: true, theme: theme) { model.onDecide?(id, .dismiss) }
            }
        }
    }

    private var replyField: some View {
        HStack(spacing: 6) {
            TextField("Antwort an \(session.projectName) …", text: Binding(
                get: { model.replyDraft(for: session.id) },
                set: { model.setReplyDraft($0, for: session.id) }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(SignalTheme.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(SignalTheme.buttonFill))
                .onSubmit { model.sendReply(to: session) }
            SignalPillButton(title: "Senden", prominent: true, compact: true, theme: theme) { model.sendReply(to: session) }
        }
    }
}
