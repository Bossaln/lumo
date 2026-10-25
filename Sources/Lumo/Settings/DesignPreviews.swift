import AppKit
import LumoCore
import SwiftUI

// Vorschauen für die Design-Optionen. Einrichtung und Einstellungen benutzen dieselben Bausteine,
// damit beide gleich aussehen und sich gleich bedienen lassen.

/// Miniatur je Signalform.
struct SignalStyleThumbnail: View {
    let style: SignalStyle
    let agent: Color

    var body: some View {
        switch style {
        case .island:
            MiniNotch(width: 84, height: 12) {
                HStack {
                    Circle().fill(agent).frame(width: 4, height: 4)
                    Spacer()
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 4, height: 4)
                }
                .padding(.horizontal, 7)
            }
        case .banner:
            MiniNotch(width: 92, height: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Spacer().frame(height: 9)
                    Capsule().fill(agent).frame(width: 40, height: 3)
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 60, height: 3)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .vertical:
            MiniNotch(width: 50, height: 40) {
                VStack(spacing: 4) {
                    Spacer().frame(height: 10)
                    Circle().fill(agent).frame(width: 7, height: 7)
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 30, height: 3)
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 22, height: 3)
                }
            }
        }
    }
}

/// Auswahl der Signalform als Karten.
struct SignalStylePicker: View {
    @Binding var selection: SignalStyle
    let agent: Color

    var body: some View {
        ChoiceCards(options: [(SignalStyle.island, L("Island")), (.banner, L("Banner")), (.vertical, L("Vertikal"))],
                    selection: $selection) { style in
            SignalStyleThumbnail(style: style, agent: agent)
        }
    }

    /// Ein Satz zur gewählten Form.
    static func explanation(_ style: SignalStyle) -> String {
        switch style {
        case .island: L("Flach neben der Kamera wie die Dynamic Island; ein Klick oder Darüberfahren klappt sie auf.")
        case .banner: L("Ein breites Banner wie eine Mitteilung auf dem iPhone, mit Antwortfeld.")
        case .vertical: L("Ein höherer Kasten unter der Notch mit allen Details und den Knöpfen.")
        }
    }
}

/// Auswahl des Hintergrunds als Karten mit der Notch in der jeweiligen Farbe.
struct BackgroundPicker: View {
    @Binding var selection: LumoCore.BackgroundStyle
    let customHex: String

    var body: some View {
        ChoiceCards(options: [(LumoCore.BackgroundStyle.black, L("Schwarz")), (.darkGray, L("Dunkelgrau")), (.custom, L("Eigene Farbe"))],
                    selection: $selection) { style in
            MiniNotch(width: 84, height: 24, background: color(for: style)) {
                HStack(spacing: 4) {
                    Circle().fill(Color.white.opacity(0.75)).frame(width: 4, height: 4)
                    Capsule().fill(Color.white.opacity(0.45)).frame(width: 30, height: 3)
                }
                .padding(.top, 10)
            }
        }
    }

    private func color(for style: LumoCore.BackgroundStyle) -> Color {
        var settings = AppSettings.default
        settings.background = style
        settings.customBackgroundHex = customHex
        return Color(hex: settings.backgroundHex())
    }
}


/// Die beiden Agentenfarben als Schildchen, so wie sie in der Notch erscheinen.
struct AgentColorChips: View {
    let claude: Color
    let codex: Color

    var body: some View {
        HStack(spacing: 10) {
            chip(.claude, color: claude, name: "Claude Code")
            chip(.codex, color: codex, name: "Codex")
        }
    }

    private func chip(_ agent: AgentKind, color: Color, name: String) -> some View {
        HStack(spacing: 6) {
            AgentBadge(agent: agent, color: color)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1))
        .shadow(color: color.opacity(0.45), radius: 6, x: 0, y: 0)
    }
}

/// Knopf, der ein Beispiel-Signal in der echten Notch zeigt.
struct TryOutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L("In der Notch ausprobieren"), systemImage: "play.circle.fill")
        }
        .controlSize(.large)
    }
}

extension SettingsStore {
    /// Bindung an eine Einstellung; jede Änderung wird sofort gespeichert.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.settings[keyPath: keyPath] = $0 })
    }

    /// Bindung einer Farbe (gespeichert als „#RRGGBB“) für einen `ColorPicker`.
    func colorBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: self.settings[keyPath: keyPath]) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                self.settings[keyPath: keyPath] = ColorHex.format(RGB(
                    r: Double(rgb.redComponent), g: Double(rgb.greenComponent), b: Double(rgb.blueComponent)))
            }
        )
    }
}
