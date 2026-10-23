import NotchaiCore
import SwiftUI

/// Höherer Kasten: Kopfzeile, Code-Block mit Detail, Knöpfe rechts unten.
struct SignalVerticalView: View {
    let content: SignalContent
    let theme: SignalTheme
    /// Antwort-Entwurf dieses Signals (liegt im `AppModel`).
    let draft: Binding<String>
    let act: (SignalAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AgentIcon(agent: content.agent, theme: theme)
                VStack(alignment: .leading, spacing: 1) {
                    Text(content.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SignalTheme.primary)
                        .lineLimit(1)
                    Text(content.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SignalTheme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                SignalStatusMark(kind: content.kind)
            }

            Spacer(minLength: 8)
            middle
            Spacer(minLength: 8)

            HStack {
                Spacer(minLength: 0)
                SignalActionRow(content: content, theme: theme, showsStatus: false, act: act)
            }
        }
        // 18 pt Rand wie im Entwurf plus die gewölbten oberen Ecken (10 pt); oben Platz für die Kamera.
        .padding(.top, 38)
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if content.kind == .done || content.kind == .error { act(.dismiss) }
        }
    }

    /// Bei Fragen das Antwortfeld, sonst das Detail als Code-Block.
    @ViewBuilder
    private var middle: some View {
        if content.kind.acceptsText {
            SignalAnswerField(text: draft, act: act)
                .id(content.id)
        } else if let detail = content.detail, !detail.isEmpty {
            Text(detail)
                .font(SignalTheme.monoFont)
                .foregroundStyle(theme.detailColor)
                .lineLimit(2)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SignalTheme.codeFill))
        }
    }
}
