import LumoCore
import SwiftUI

/// Höherer Kasten: Kopfzeile, Code-Block mit Detail, Knöpfe rechts unten. „Fertig“ und „Fehler“ zeigen nur die
/// Kopfzeile (`NotchPresentation.verticalCompact`), „Schließen“ steht dann rechts darin.
struct SignalVerticalView: View {
    let content: SignalContent
    let theme: SignalTheme
    /// Höhe der Kamera-Aussparung; der Inhalt beginnt darunter.
    let notchHeight: CGFloat
    /// Antwort-Entwurf dieses Signals (liegt im `AppModel`).
    let draft: Binding<String>
    var choices = SignalChoices()
    /// Hinweis „+1 Zeile“: die Anfrage mit dem ganzen Befehl zeigen.
    var showFull: () -> Void = {}
    let act: (SignalAction) -> Void

    /// 18 pt Rand wie im Entwurf plus die gewölbten oberen Ecken (10 pt).
    private static let sidePadding: CGFloat = 28
    /// Nur Kopfzeile: gleicher Abstand unter der Kamera und am unteren Rand (passt zu
    /// `NotchGeometry.verticalCompactExtraHeight`).
    private static let compactPadding: CGFloat = 12
    /// So viele Zeilen des ganzen Befehls zeigt der Code-Block; der Rest steht in den Sessions.
    private static let commandLines = 5

    private var isCompact: Bool { !content.kind.isAwaitingOwner }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCompact {
                Spacer(minLength: 8)
                middle
                Spacer(minLength: 8)
                HStack {
                    Spacer(minLength: 0)
                    SignalActionRow(content: content, theme: theme, showsStatus: false, choices: choices, act: act)
                }
            }
        }
        .padding(.top, notchHeight + (isCompact ? Self.compactPadding : 6))
        .padding(.horizontal, Self.sidePadding)
        .padding(.bottom, isCompact ? Self.compactPadding : 16)
        // Allein steht die Kopfzeile mittig zwischen Kamera und unterem Rand.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .center : .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCompact { act(.dismiss) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentIcon(agent: content.agent, theme: theme)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(content.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SignalTheme.primary)
                        .lineLimit(1)
                    SignalProgressBadge(progress: content.progress)
                }
                Text(content.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SignalTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            SignalStatusMark(kind: content.kind)
            if content.kind == .error {
                SignalPillButton(title: L("Schließen"), compact: true, theme: theme) { act(.dismiss) }
            }
        }
    }

    /// Bei Fragen das Antwortfeld, sonst das Detail als Code-Block: bei gekürzten Befehlen der ganze Befehl.
    @ViewBuilder
    private var middle: some View {
        if content.kind.acceptsText {
            SignalAnswerField(text: draft, act: act, submit: content.multiSelect ? choices.submit : nil)
                .id(content.id)
        } else if let detail = content.fullDetail ?? content.detail, !detail.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                Text(detail)
                    .font(SignalTheme.monoFont)
                    .foregroundStyle(theme.detailColor)
                    .lineLimit(content.fullDetail == nil ? 2 : Self.commandLines)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SignalDetailNote(note: content.detailNote, theme: theme, open: showFull)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SignalTheme.codeFill))
        }
    }
}
