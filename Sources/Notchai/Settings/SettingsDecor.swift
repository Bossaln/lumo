import NotchaiCore
import SwiftUI

/// Bereiche des Einstellungsfensters, gruppiert wie in den Systemeinstellungen.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, updates, notch, agents, sessions, music, office, shelf, notes, developer

    var id: String { rawValue }

    /// Gruppen der Seitenleiste; „Entwickler“ nur, wenn die Entwickleroptionen eingeschaltet sind.
    static func groups(developer: Bool) -> [[SettingsPane]] {
        [[.general, .updates], [.notch, .agents, .sessions], [.music, .office, .shelf, .notes]] + (developer ? [[.developer]] : [])
    }

    var title: String {
        switch self {
        case .general: L("Allgemein")
        case .updates: L("Softwareupdate")
        case .notch: L("Notch")
        case .agents: L("Agenten")
        case .sessions: L("Sessions")
        case .music: L("Musik")
        case .office: L("Büro")
        case .shelf: L("Ablage")
        case .notes: L("Notizen")
        case .developer: L("Entwickler")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .notch: "rectangle.topthird.inset.filled"
        case .agents: "link"
        case .sessions: "terminal.fill"
        case .music: "music.note"
        case .office: "building.2.fill"
        case .shelf: "tray.full.fill"
        case .notes: "note.text"
        case .developer: "hammer.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            L("Start beim Anmelden, Einrichtung und alles über notchai.")
        case .updates:
            L("notchai sucht neue Versionen und installiert sie auf deinen Klick – über Homebrew oder aus deinem Quellordner.")
        case .notch:
            L("Form, Farben und Bewegung der Notch – vom ruhigen Schwarz bis zum leuchtenden Signal.")
        case .agents:
            L("Verbinde Claude Code und Codex, damit Fragen und Freigaben direkt in der Notch landen.")
        case .sessions:
            L("Was die Notch über laufende Sessions zeigt und wann sie sich bei dir meldet.")
        case .music:
            L("Was gerade läuft, mit Cover, Steuerung und Leuchten – und welche Apps die Notch zeigen darf.")
        case .office:
            L("Deine Lagerhalle, in der Claude Code und Codex arbeiten, Red Bull holen und schlafen.")
        case .shelf:
            L("Zieh Dateien auf die Notch: per AirDrop senden oder kurz ablegen und später wieder herausziehen.")
        case .notes:
            L("Zweimal ⌃ drücken und eine Schnellnotiz direkt in der Notch schreiben, egal welche App vorn ist.")
        case .developer:
            L("Werkzeuge zum Ausprobieren: Signale auslösen, Rohdaten kopieren und notchai komplett zurücksetzen.")
        }
    }

    /// Verlauf der Symbol-Kachel (oben, unten).
    var colors: (Color, Color) {
        switch self {
        case .general: (Self.rgb(0.62, 0.62, 0.65), Self.rgb(0.42, 0.42, 0.45))
        case .updates: (Self.rgb(0.25, 0.62, 1.0), Self.rgb(0.0, 0.42, 0.94))
        case .notch: (Self.rgb(0.30, 0.30, 0.33), Self.rgb(0.06, 0.06, 0.07))
        case .agents: (Self.rgb(0.78, 0.42, 1.0), Self.rgb(0.55, 0.22, 0.88))
        case .sessions: (Self.rgb(1.0, 0.66, 0.12), Self.rgb(0.98, 0.42, 0.0))
        case .music: (Self.rgb(1.0, 0.33, 0.45), Self.rgb(0.92, 0.12, 0.30))
        case .office: (Self.rgb(0.25, 0.85, 0.62), Self.rgb(0.07, 0.62, 0.45))
        case .shelf: (Self.rgb(1.0, 0.74, 0.22), Self.rgb(0.96, 0.52, 0.02))
        case .notes: (Self.rgb(1.0, 0.88, 0.32), Self.rgb(0.95, 0.72, 0.08))
        case .developer: (Self.rgb(0.36, 0.40, 0.98), Self.rgb(0.18, 0.18, 0.62))
        }
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b)
    }
}

/// Farbige Kachel mit weißem Symbol, wie in den Systemeinstellungen.
struct SettingsIcon: View {
    let pane: SettingsPane
    let size: CGFloat

    var body: some View {
        let colors = pane.colors
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: pane.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 0.5)
            )
            .frame(width: size, height: size)
    }
}

/// Kopf einer Seite: großes Symbol mit farbigem Schein, Titel und Beschreibung, linksbündig wie eine Überschrift.
struct SettingsHero: View {
    let pane: SettingsPane
    var namespace: Namespace.ID?

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            icon
                .shadow(color: pane.colors.1.opacity(0.55), radius: 22, x: 0, y: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(pane.title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Lux.primary)
                Text(pane.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Lux.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var icon: some View {
        if let namespace {
            SettingsIcon(pane: pane, size: 68).matchedGeometryEffect(id: pane, in: namespace)
        } else {
            SettingsIcon(pane: pane, size: 68)
        }
    }
}

/// Eine Seite: Kopf und darunter die Abschnitte als Karten (`LuxSections`).
struct SettingsPage<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: () -> Content
    @Environment(\.settingsNamespace) private var namespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                SettingsHero(pane: pane, namespace: namespace)
                LuxSections(content: content)
            }
            .padding(.horizontal, 56)
            .padding(.top, 84)
            .padding(.bottom, 48)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .luxControls()
    }
}

/// Namensraum, in dem die Symbol-Kachel von der Startseite in den Kopf der Seite fliegt.
private struct SettingsNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var settingsNamespace: Namespace.ID? {
        get { self[SettingsNamespaceKey.self] }
        set { self[SettingsNamespaceKey.self] = newValue }
    }
}

/// Auswahl als Karten mit Vorschaubild, wie „Erscheinungsbild“ in den Systemeinstellungen.
struct ChoiceCards<Value: Hashable, Preview: View>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @ViewBuilder let preview: (Value) -> Preview

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    VStack(spacing: 7) {
                        preview(option.value)
                            .frame(width: 112, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                                  lineWidth: selected ? 3 : 1)
                            )
                            .shadow(color: Color.black.opacity(selected ? 0.18 : 0.08), radius: 4, x: 0, y: 2)
                        Text(option.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Schreibtisch-Hintergrund für Vorschaubilder.
struct DesktopBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(.sRGB, red: 0.16, green: 0.19, blue: 0.48),
                                Color(.sRGB, red: 0.46, green: 0.26, blue: 0.62),
                                Color(.sRGB, red: 0.96, green: 0.56, blue: 0.46)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Kleine Notch auf dem Schreibtisch, für die Auswahlkarten.
struct MiniNotch<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var background: Color = .black
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            DesktopBackdrop()
            NotchShape(bottomRadius: min(10, height / 2.4), topCornerRadius: 3)
                .fill(background)
                .frame(width: width, height: height)
                .overlay(alignment: .top) { content().frame(width: width, height: height) }
        }
    }
}

/// Live-Vorschau der Notch: Beim Darüberfahren klappt sie mit dem eingestellten Gummi-Effekt in den gewählten
/// Signalstil auf (Island, Banner oder Vertikal), leuchtet in der Claude-Farbe und zeigt ein Beispiel-Signal.
struct NotchPreviewCard: View {
    let settings: AppSettings
    @ViewState private var expanded = false

    /// Maße der eingeklappten Notch in der Vorschau.
    private static let notchWidth: CGFloat = 120
    private static let notchHeight: CGFloat = 24

    var body: some View {
        let spring = NotchSpring(bounce: settings.notchBounce)
        let agent = Color(hex: settings.claudeColorHex)
        let glow = settings.glowEnabled ? min(1, settings.glowIntensity / 0.6) : 0
        let style = settings.signalStyle
        let size = expanded ? Self.size(for: style) : CGSize(width: Self.notchWidth, height: Self.notchHeight)
        let radii = expanded ? Self.radii(for: style) : (top: 0, bottom: 9)
        let shape = NotchShape(bottomRadius: radii.bottom, topCornerRadius: radii.top)
        ZStack(alignment: .top) {
            DesktopBackdrop()
            // Menüleiste
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .frame(height: Self.notchHeight)
            shape
                .fill(Color(hex: settings.backgroundHex()))
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    if expanded {
                        previewSignal(style: style, agent: agent)
                            .frame(width: size.width, height: size.height)
                            .transition(.notchContent)
                            .id(style)
                    }
                }
                .clipShape(shape)
                .background {
                    shape
                        .fill(Color.black)
                        .shadow(color: agent.opacity(expanded ? 0.65 * glow : 0), radius: 14)
                        .shadow(color: agent.opacity(expanded ? 0.35 * glow : 0), radius: 3)
                }
                .animation(.spring(response: spring.response, dampingFraction: spring.dampingFraction), value: expanded)
                .animation(.spring(response: spring.response, dampingFraction: spring.dampingFraction), value: style)
        }
        .frame(height: 176)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottom) {
            Text(expanded ? L("Gummi-Effekt: {0}", settings.notchBounce == 0 ? L("aus")
                                  : settings.notchBounce.formatted(.percent.precision(.fractionLength(0))))
                          : L("Zum Ausprobieren mit dem Zeiger darüberfahren"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.bottom, 10)
        }
        .contentShape(Rectangle())
        .onHover { expanded = $0 }
        .padding(.vertical, 4)
    }

    /// Form je Stil, im Maßstab der Vorschau (die Notch ist hier 120 statt etwa 190 pt breit).
    private static func size(for style: SignalStyle) -> CGSize {
        switch style {
        case .island: CGSize(width: 300, height: notchHeight)
        case .banner: CGSize(width: 340, height: notchHeight + 40)
        case .vertical: CGSize(width: 230, height: notchHeight + 100)
        }
    }

    private static func radii(for style: SignalStyle) -> (top: CGFloat, bottom: CGFloat) {
        switch style {
        case .island: (5, 11)
        case .banner: (8, 22)
        case .vertical: (8, 18)
        }
    }

    @ViewBuilder
    private func previewSignal(style: SignalStyle, agent: Color) -> some View {
        switch style {
        case .island:
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(agent).frame(width: 6, height: 6).shadow(color: agent, radius: 3)
                    Text("Claude").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white)
                    Text("npm test").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(agent).lineLimit(1)
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: Self.notchWidth)
                HStack(spacing: 4) {
                    Circle().fill(Color.white.opacity(0.16)).frame(width: 15, height: 15)
                        .overlay(Image(systemName: "xmark").font(.system(size: 6.5, weight: .bold)).foregroundStyle(Color.white))
                    Circle().fill(agent).frame(width: 15, height: 15)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 6.5, weight: .bold)).foregroundStyle(Color.black))
                }
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .banner:
            HStack(spacing: 8) {
                AgentIconMini(color: agent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "notchai · Claude").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white)
                    Text(L("Möchte ausführen:")).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.6))
                        + Text(" npm test").font(.system(size: 9, design: .monospaced)).foregroundStyle(agent)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                pill(L("Ablehnen"), fill: Color.white.opacity(0.14), text: .white)
                pill(L("Erlauben"), fill: agent, text: .black)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 9)
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .vertical:
            VStack(alignment: .leading, spacing: 7) {
                Spacer().frame(height: Self.notchHeight)
                HStack(spacing: 7) {
                    AgentIconMini(color: agent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "notchai · Claude").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white)
                        Text(L("Möchte ausführen:")).font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                Text("npm test")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(agent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.06)))
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    pill(L("Ablehnen"), fill: Color.white.opacity(0.14), text: .white)
                    pill(L("Erlauben"), fill: agent, text: .black)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func pill(_ title: String, fill: Color, text: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }
}

/// Kleines Agentensymbol für die Vorschau.
private struct AgentIconMini: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Image(systemName: "asterisk").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.white))
    }
}

/// Vorschau der eingeklappten Musikanzeige: Cover links, tanzende Balken rechts.
struct MusicPreviewCard: View {
    let settings: AppSettings

    var body: some View {
        let cover = LinearGradient(colors: [Color(.sRGB, red: 1.0, green: 0.36, blue: 0.5),
                                            Color(.sRGB, red: 0.55, green: 0.18, blue: 0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
        let pink = Color(.sRGB, red: 1.0, green: 0.38, blue: 0.58)
        ZStack(alignment: .top) {
            DesktopBackdrop()
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .frame(height: 24)
            NotchShape(bottomRadius: 11, topCornerRadius: 5)
                .fill(Color(hex: settings.backgroundHex()))
                .frame(width: 230, height: 30)
                .overlay {
                    HStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(cover)
                            .frame(width: 19, height: 19)
                        Spacer()
                        DancingBars(color: pink, playing: settings.musicEnabled)
                            .scaleEffect(0.85)
                    }
                    .padding(.horizontal, 15)
                }
                .background {
                    NotchShape(bottomRadius: 11, topCornerRadius: 5)
                        .fill(Color.black)
                        .shadow(color: pink.opacity(settings.musicCoverGlow ? 0.55 : 0), radius: 10)
                }
                .opacity(settings.musicEnabled ? 1 : 0.4)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 4)
    }
}

/// Grüner, orangefarbener oder grauer Punkt mit Text (Verbindungsstatus).
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
