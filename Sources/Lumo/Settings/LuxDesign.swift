import LumoCore
import SwiftUI

/// Gestaltung von Einstellungen und Einführung: tiefschwarz wie die Notch, feine Linien, weiße Schrift, Farbe nur
/// als Schein. Eigene Karten, Schalter und Knöpfe statt der grauen Formulare von macOS.
enum Lux {
    static let background = Color.black
    /// Fläche einer Karte und ihr Rand: kaum heller als der Grund.
    static let card = Color.white.opacity(0.045)
    static let cardHover = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.09)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let cardRadius: CGFloat = 20
    /// Weich und kurz, für alles, was auf Zeiger und Klick reagiert.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b)
    }
}

// MARK: - Hintergrund

/// Schwarzer Grund mit drei großen, unscharfen Farbschleiern, die langsam treiben. Ruhig genug zum Lesen,
/// lebendig genug, dass das Fenster atmet.
struct LuxBackdrop: View {
    let colors: [Color]
    /// Wie kräftig die Schleier sind (0…1).
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Lux.background
                    ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { index, color in
                        let phase = Double(index) * 2.1
                        let x = sin(t / (11 + Double(index) * 3) + phase) * size.width * 0.28
                        let y = cos(t / (13 + Double(index) * 2) + phase) * size.height * 0.22
                        Circle()
                            .fill(color.opacity(0.30 * intensity))
                            .frame(width: size.width * 0.62, height: size.width * 0.62)
                            .blur(radius: size.width * 0.16)
                            .offset(x: x + Self.anchors[index].x * size.width, y: y + Self.anchors[index].y * size.height)
                    }
                    // Feine Körnung gegen Farbstufen im Verlauf.
                    LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Ausgangslage der Schleier relativ zur Mitte: oben links, unten rechts, oben rechts.
    private static let anchors: [CGPoint] = [CGPoint(x: -0.32, y: -0.34), CGPoint(x: 0.34, y: 0.36), CGPoint(x: 0.30, y: -0.30)]
}

// MARK: - Karten

/// Abgerundete Glaskarte mit feinem Rand.
struct LuxCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).fill(Lux.card))
            .overlay(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).strokeBorder(Lux.hairline, lineWidth: 1))
    }
}

/// Überschrift über einer Karte: klein, gesperrt, grau.
struct LuxCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Lux.tertiary)
            .padding(.leading, 6)
    }
}

/// Die Abschnitte einer Seite (`Section` im Code) als Karten: Überschrift darüber, Zeilen mit feinen Linien
/// dazwischen, Fußnote darunter. Auf macOS 14 (ohne `Group(sections:)`) bleibt es beim gruppierten Formular.
struct LuxSections<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 15, *) {
            VStack(alignment: .leading, spacing: 26) {
                Group(sections: content()) { sections in
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 9) {
                            if !section.header.isEmpty {
                                section.header
                                    .font(.system(size: 11, weight: .semibold))
                                    .textCase(.uppercase)
                                    .tracking(1.2)
                                    .foregroundStyle(Lux.tertiary)
                                    .padding(.leading, 6)
                            }
                            LuxCard(padding: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Group(subviews: section.content) { rows in
                                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                            if index > 0 {
                                                Rectangle().fill(Lux.hairline).frame(height: 1).padding(.leading, 18)
                                            }
                                            row
                                                .padding(.horizontal, 18)
                                                .padding(.vertical, 12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            if !section.footer.isEmpty {
                                section.footer
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Lux.secondary)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
        } else {
            Form { content() }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
        }
    }
}

// MARK: - Bedienelemente

/// Schalter: dunkle Kapsel, eingeschaltet in Weiß mit schwarzem Knopf – wie ein Lichtschalter in der Nacht.
struct LuxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .foregroundStyle(Lux.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LuxSwitch(isOn: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Lux.spring) { configuration.isOn.toggle() } }
    }
}

private struct LuxSwitch: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Capsule()
            .fill(isOn ? Color.white : Color.white.opacity(0.14))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.10), lineWidth: 1))
            .frame(width: 40, height: 23)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.black : Color.white.opacity(0.85))
                    .frame(width: 17, height: 17)
                    .padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(Lux.spring, value: isOn)
    }
}

/// Zeile „Beschriftung … Wert“ ohne Formular: links weiß, rechts grau.
struct LuxLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            configuration.label
                .foregroundStyle(Lux.primary)
            Spacer(minLength: 12)
            configuration.content
                .foregroundStyle(Lux.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Knopf als dunkle Kapsel; `prominent` weiß mit schwarzer Schrift, wie die Hauptaktion bei Apple.
struct LuxButtonStyle: ButtonStyle {
    var prominent = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        LuxButtonBody(configuration: configuration, prominent: prominent, large: large)
    }
}

private struct LuxButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let large: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: large ? 14 : 12.5, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Lux.primary)
            .padding(.horizontal, large ? 26 : 14)
            .padding(.vertical, large ? 11 : 6.5)
            .background(
                Capsule().fill(prominent ? Color.white.opacity(hovering ? 1 : 0.92)
                                         : Color.white.opacity(hovering ? 0.16 : 0.10))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.08), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    /// Schalter, Zeilen, Knöpfe und Schieberegler im Stil von `Lux` für alles darin.
    func luxControls() -> some View {
        self
            .toggleStyle(LuxToggleStyle())
            .labeledContentStyle(LuxLabeledContentStyle())
            .buttonStyle(LuxButtonStyle())
            .tint(Color.white)
            .font(.system(size: 13))
            .foregroundStyle(Lux.primary)
            .environment(\.colorScheme, .dark)
    }
}
