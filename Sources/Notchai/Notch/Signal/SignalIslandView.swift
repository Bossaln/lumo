import NotchaiCore
import SwiftUI

/// Flache Island: so hoch wie die Notch, links wer etwas will, rechts Hinweis und Knöpfe.
/// Ein Klick auf die Fläche klappt sie zum Banner auf.
struct SignalIslandView: View {
    let content: SignalContent
    let theme: SignalTheme
    let notchWidth: CGFloat
    /// Breite je Seite neben der Kamera; beide Seiten sind fest so breit, damit die Lücke genau unter der Kamera liegt.
    let sideWidth: CGFloat
    let act: (SignalAction) -> Void
    let expand: () -> Void
    /// Meldet den Knopfbereich rechts in Panel-Koordinaten (`nil`, wenn die Island verschwindet).
    let reportButtonArea: (CGRect?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: sideWidth, alignment: .leading)
                .clipped()

            // Über der Kamera bleibt alles frei.
            Color.clear.frame(width: notchWidth)

            // Rechtsbündig: Wird es eng, bleiben ✕/✓ in der Form, statt dass der Inhalt mittig überläuft.
            trailingArea
                .frame(width: sideWidth, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
    }

    /// Punkt, Agentname und Detail; das Detail bekommt den Rest und wird mit „…“ gekürzt.
    private var leading: some View {
        ViewThatFits(in: .horizontal) {
            leadingRow(showsDetail: true)
            leadingRow(showsDetail: false)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
    }

    private func leadingRow(showsDetail: Bool) -> some View {
        HStack(spacing: 6) {
            PulseDot(color: theme.agentColor)
            Text(content.agent.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(SignalTheme.primary)
                .fixedSize()
            if showsDetail {
                Text(content.detail ?? content.subtitle)
                    .font(SignalTheme.monoFont)
                    .foregroundStyle(theme.detailColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Erst ab etwa vier Zeichen zeigen, sonst bliebe nur ein abgeschnittener Buchstabe.
                    .frame(minWidth: 28, idealWidth: 28, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// „Erlauben?“/„Frage“ und die runden Knöpfe; über diesem Bereich klappt Hover nicht auf.
    private var trailingArea: some View {
        ViewThatFits(in: .horizontal) {
            trailing(withPrompt: true)
            trailing(withPrompt: false)
        }
        .padding(.leading, 3)
        // 8 pt reichen, damit der runde ✓-Knopf ganz innerhalb der unteren Rundung liegt.
        .padding(.trailing, 8)
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { reportButtonArea($0) }
        .onDisappear { reportButtonArea(nil) }
    }

    @ViewBuilder
    private func trailing(withPrompt: Bool) -> some View {
        HStack(spacing: 4) {
            if withPrompt {
                Text(content.kind.islandPrompt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SignalTheme.muted)
                    .fixedSize()
                    .padding(.trailing, 1)
            }
            switch content.kind {
            case .permission:
                SignalRoundButton(symbol: "xmark", theme: theme) { act(.deny) }
                SignalRoundButton(symbol: "checkmark", prominent: true, theme: theme) { act(.allow) }
            case .question:
                SignalRoundButton(symbol: "chevron.down", theme: theme, action: expand)
            case .done, .error:
                SignalStatusMark(kind: content.kind, size: 16)
            }
        }
    }
}
