import NotchaiCore
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Farbe aus "#RRGGBB"; bei ungültigem Wert die Ersatzfarbe.
    init(hex: String, fallback: RGB = RGB(r: 0, g: 0, b: 0)) {
        self.init(ColorHex.parse(hex) ?? fallback)
    }
}

/// Farben eines Signals. Die Agentenfarbe kommt aus den Einstellungen.
struct SignalTheme {
    let agentColor: Color
    /// Aufgehellte Agentenfarbe für Monospace-Details (wie #FFB27A im Entwurf).
    let detailColor: Color
    let agentDark: Color

    init(agentHex: String) {
        let rgb = ColorHex.parse(agentHex) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        agentColor = Color(rgb)
        detailColor = Color(RGB(r: rgb.r + (1 - rgb.r) * 0.45, g: rgb.g + (1 - rgb.g) * 0.45, b: rgb.b + (1 - rgb.b) * 0.45))
        agentDark = Color(RGB(r: rgb.r * 0.82, g: rgb.g * 0.82, b: rgb.b * 0.82))
    }

    static let primary = Color.white
    static let muted = Color(hex: "#9A9A9A")
    static let buttonFill = Color(hex: "#2A2A2A")
    static let buttonText = Color(hex: "#DDDDDD")
    static let codeFill = Color(hex: "#111111")
    static let green = Color(hex: "#30D158")
    static let red = Color(hex: "#FF453A")

    static let monoFont = Font.system(size: 11.5, design: .monospaced)
}

/// Abgerundetes Agentensymbol (26 pt) mit Verlauf in Agentenfarbe.
struct AgentIcon: View {
    let agent: SignalAgent
    let theme: SignalTheme
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [theme.detailColor, theme.agentDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: agent == .claude ? "asterisk" : "terminal")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

/// Kleiner pulsierender Punkt links in der Island.
struct PulseDot: View {
    let color: Color
    @ViewState private var bright = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color, radius: bright ? 5 : 2)
            .opacity(bright ? 1 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}

/// Grüner Haken für „fertig“, rotes Ausrufezeichen für „Fehler“.
struct SignalStatusMark: View {
    let kind: SignalKind
    var size: CGFloat = 18

    var body: some View {
        switch kind {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(SignalTheme.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: size)).foregroundStyle(SignalTheme.red)
        default:
            EmptyView()
        }
    }
}

/// Länglicher Knopf („Ablehnen“, „Erlauben“, Auswahl-Optionen).
struct SignalPillButton: View {
    let title: String
    var prominent = false
    /// Flacher für die zweizeilige Frage im Banner.
    var compact = false
    let theme: SignalTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, compact ? 11 : 13)
                .padding(.vertical, compact ? 4.5 : 6)
                .foregroundStyle(prominent ? Color.black : SignalTheme.buttonText)
                .background(Capsule().fill(prominent ? theme.agentColor : SignalTheme.buttonFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Runder 22-pt-Knopf mit ✕ oder ✓ für die Island.
struct SignalRoundButton: View {
    let symbol: String
    var prominent = false
    let theme: SignalTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(prominent ? Color.black : SignalTheme.buttonText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(prominent ? theme.agentColor : SignalTheme.buttonFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Textfeld „Antworten …“; Return schickt die Antwort ab. Der Text gehört dem Signal (Entwurf im `AppModel`),
/// nicht der Ansicht, damit er weder beim Zuklappen verloren geht noch bei einem anderen Signal auftaucht.
struct SignalAnswerField: View {
    @Binding var text: String
    let act: (SignalAction) -> Void
    /// Flacher für die zweizeilige Frage im Banner.
    var compact = false

    var body: some View {
        TextField(L("Antworten …"), text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(SignalTheme.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 4.5 : 6)
            .background(Capsule().fill(SignalTheme.buttonFill))
            .onSubmit {
                if let answer = SignalAction.typedAnswer(text) { act(answer) }
            }
    }
}

/// Knöpfe je Anlass, gemeinsam für Banner und Kasten.
struct SignalActionRow: View {
    let content: SignalContent
    let theme: SignalTheme
    var showsStatus = true
    let act: (SignalAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch content.kind {
            case .permission:
                SignalPillButton(title: L("Ablehnen"), theme: theme) { act(.deny) }
                SignalPillButton(title: L("Erlauben"), prominent: true, theme: theme) { act(.allow) }
            case .question:
                ForEach(content.kind.visibleOptions, id: \.self) { option in
                    SignalPillButton(title: option, theme: theme) { act(.answer(option)) }
                }
                // Schließen: Der Agent fragt dann selbst im Terminal bzw. in der App.
                SignalRoundButton(symbol: "xmark", theme: theme) { act(.dismiss) }
            case .done:
                if showsStatus { SignalStatusMark(kind: .done) }
            case .error:
                if showsStatus { SignalStatusMark(kind: .error) }
                SignalPillButton(title: L("Schließen"), theme: theme) { act(.dismiss) }
            }
        }
    }
}

/// Untertitel in Grau, Detail in Monospace und aufgehellter Agentenfarbe dahinter.
func signalSubtitleText(_ content: SignalContent, theme: SignalTheme, includeDetail: Bool) -> Text {
    let subtitle = Text(content.subtitle).foregroundColor(SignalTheme.muted)
    guard includeDetail, let detail = content.detail, !detail.isEmpty else { return subtitle }
    return subtitle + Text(" ") + Text(detail).font(SignalTheme.monoFont).foregroundColor(theme.detailColor)
}
