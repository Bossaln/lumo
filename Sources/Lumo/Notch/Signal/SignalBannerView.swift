import LumoCore
import SwiftUI

/// Breites Banner wie eine iPhone-Mitteilung: Symbol, Text und Knöpfe in einer Zeile unter der Kamera.
/// Bei einer Frage stehen Symbol und Titel im Band neben der Kamera, darunter die Frage und eine Zeile
/// mit Antwortfeld und bis zu vier Auswahl-Knöpfen.
struct SignalBannerView: View {
    let content: SignalContent
    let theme: SignalTheme
    /// Breite der Kamera-Aussparung; darunter wird nichts gezeichnet.
    let notchWidth: CGFloat
    /// Höhe des Bands neben der Kamera (= Notch-Höhe).
    let bandHeight: CGFloat
    /// Antwort-Entwurf dieses Signals (liegt im `AppModel`, übersteht Zu- und Aufklappen).
    let draft: Binding<String>
    var choices = SignalChoices()
    /// Hinweis „+1 Zeile“: die Anfrage mit dem ganzen Befehl zeigen.
    var showFull: () -> Void = {}
    let act: (SignalAction) -> Void

    /// 16 pt Rand wie im Entwurf plus die gewölbten oberen Ecken (10 pt).
    private static let sidePadding: CGFloat = 26

    var body: some View {
        Group {
            if case .question = content.kind {
                questionLayout
            } else {
                rowLayout
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissIfInformational() }
    }

    /// Freigabe, Fertig, Fehler: alles in einer Zeile unten.
    private var rowLayout: some View {
        HStack(spacing: 12) {
            AgentIcon(agent: content.agent, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SignalTheme.primary)
                HStack(spacing: 6) {
                    signalSubtitleText(content, theme: theme, includeDetail: true)
                        .font(.system(size: 11.5))
                    // Gekürzter Befehl: Der Hinweis steht für sich und wird nie mit abgeschnitten.
                    SignalDetailNote(note: content.detailNote, theme: theme, open: showFull)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            SignalActionRow(content: content, theme: theme, act: act)
                .fixedSize()
        }
        .padding(.horizontal, Self.sidePadding)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Frage: Titel im Band links der Kamera, Frage und Antwortzeile in den 52 pt darunter.
    private var questionLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    AgentIcon(agent: content.agent, theme: theme, size: 20)
                    Text(content.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SignalTheme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    SignalProgressBadge(progress: content.progress)
                }
                .padding(.leading, Self.sidePadding)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                // Unter der Kamera bleibt das Band frei.
                Color.clear.frame(width: notchWidth)
                Color.clear.frame(maxWidth: .infinity)
            }
            .frame(height: bandHeight)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                questionText
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    SignalAnswerField(text: draft, act: act, compact: true, submit: content.multiSelect ? choices.submit : nil)
                        .id(content.id)
                        .frame(minWidth: 110, maxWidth: .infinity)
                    // Lange Auswahl-Texte werden mit „…“ gekürzt, statt aus dem Banner zu laufen.
                    SignalOptionButtons(content: content, theme: theme, compact: true, choices: choices, act: act)
                        .layoutPriority(1)
                    // Schließen: Der Agent fragt dann selbst im Terminal bzw. in der App.
                    SignalRoundButton(symbol: "xmark", theme: theme) { act(.dismiss) }
                        .layoutPriority(2)
                }
            }
            .padding(.horizontal, Self.sidePadding)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Die Frage in Weiß, ein Detail dahinter in Monospace.
    private var questionText: Text {
        let question = Text(content.subtitle).foregroundColor(SignalTheme.primary)
        guard let detail = content.detail, !detail.isEmpty else { return question }
        return question + Text(" ") + Text(detail).font(SignalTheme.monoFont).foregroundColor(theme.detailColor)
    }

    /// „Fertig“ und „Fehler“ schließt ein Klick irgendwohin.
    private func dismissIfInformational() {
        if content.kind == .done || content.kind == .error { act(.dismiss) }
    }
}
