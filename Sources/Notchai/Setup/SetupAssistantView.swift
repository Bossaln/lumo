import AppKit
import ApplicationServices
import NotchaiCore
import SwiftUI

/// Einrichtungs-Assistent: links die Schritte auf farbigem Grund, rechts der aktuelle Schritt mit Symbol,
/// Erklärung und interaktiven Vorschauen. Hooks verbinden, Design wählen (mit „In der Notch ausprobieren“),
/// Berechtigungen. Jeder Schritt lässt sich überspringen; alles ist später in den Einstellungen änderbar.
struct SetupAssistantView: View {
    let setup: SetupController
    let settingsStore: SettingsStore
    /// Zeigt ein Beispiel-Signal in der echten Notch.
    let tryOut: () -> Void
    let finish: () -> Void

    @ViewState private var step: SetupStep = .welcome

    /// Hook-Ereignisse, die notchai nur meldet (ohne die, auf die es antwortet).
    private static let claudeEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, StopFailure, SubagentStart, SubagentStop"
    private static let codexEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        content
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 46)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                Divider()
                footer
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 820, height: 580)
        .onAppear { setup.refresh() }
    }

    private var settings: AppSettings { settingsStore.settings }
    private var claude: Color { Color(hex: settings.claudeColorHex) }
    private var codex: Color { Color(hex: settings.codexColorHex) }

    private func go(to target: SetupStep) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { step = target }
    }

    // MARK: - Seitenleiste

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Self.rgb(0.09, 0.07, 0.18), Self.rgb(0.18, 0.09, 0.27)], startPoint: .top, endPoint: .bottom)
            // Weicher Schein in den Agentenfarben.
            Circle().fill(claude.opacity(0.45)).frame(width: 260, height: 260).blur(radius: 90).offset(x: -90, y: -60)
            Circle().fill(codex.opacity(0.40)).frame(width: 240, height: 240).blur(radius: 90).offset(x: 60, y: 380)
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("notchai")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(L("Einrichtung"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .padding(.top, 46)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SetupStep.allCases, id: \.self) { item in
                        stepRow(item)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .clipped()
    }

    private func stepRow(_ item: SetupStep) -> some View {
        let info = StepInfo(item)
        let current = item == step
        let done = item.rawValue < step.rawValue
        return Button {
            go(to: item)
        } label: {
            HStack(spacing: 10) {
                StepTile(info: info, size: 24, active: current || done)
                Text(info.short)
                    .font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(Color.white.opacity(current ? 1 : done ? 0.85 : 0.55))
                Spacer(minLength: 0)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(current ? 0.14 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kopf und Fuß

    private var header: some View {
        let info = StepInfo(step)
        return HStack(spacing: 16) {
            if step == .welcome {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: claude.opacity(0.5), radius: 14, x: 0, y: 4)
            } else {
                StepTile(info: info, size: 56, active: true)
                    .shadow(color: info.colors.1.opacity(0.45), radius: 12, x: 0, y: 5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.system(size: 26, weight: .bold))
                Text(info.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(width: 150, height: 5)
                Capsule().fill(LinearGradient(colors: [claude, codex], startPoint: .leading, endPoint: .trailing))
                    .frame(width: CGFloat(max(8, 150 * step.progress)), height: 5)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
            Text(L("Schritt {0} von {1}", step.rawValue + 1, SetupStep.allCases.count))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if step == .welcome {
                Button(L("Später")) { finish() }
            } else if let previous = step.previous, step != .done {
                Button(L("Zurück")) { go(to: previous) }
            }
            if step == .claude || step == .codex {
                Button(L("Überspringen")) { advance() }
            }
            primaryButton
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .welcome:
            Button(L("Los geht's")) { advance() }
        case .claude:
            if setup.status?.claudeInstalled == true {
                Button(L("Weiter")) { advance() }
            } else {
                Button(L("Claude Code verbinden")) {
                    setup.connectClaude()
                    if setup.status?.claudeInstalled == true { advance() }
                }
            }
        case .codex:
            if setup.status?.codexInstalled == true {
                Button(L("Weiter")) { advance() }
            } else {
                Button(L("Codex verbinden")) {
                    setup.connectCodex()
                    if setup.status?.codexInstalled == true { advance() }
                }
            }
        case .done:
            Button(L("Fertig")) { finish() }
        default:
            Button(L("Weiter")) { advance() }
        }
    }

    private func advance() {
        if let next = step.next { go(to: next) } else { finish() }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .claude: claudeStep
        case .codex: codexStep
        case .signalStyle: signalStyleStep
        case .appearance: appearanceStep
        case .sessions: sessionsStep
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(symbol: "bell.badge.fill", color: Self.rgb(1.0, 0.55, 0.25), title: L("Signale"),
                       text: L("Fragen, Freigaben, „Fertig“ und Fehler erscheinen direkt in der Notch. Erlauben, ablehnen oder antworten, ohne das Fenster zu wechseln."))
            FeatureRow(symbol: "rectangle.stack.fill", color: Self.rgb(0.35, 0.6, 1.0), title: L("Sessions"),
                       text: L("Alle laufenden Claude-Code- und Codex-Sessions auf einen Blick, mit letztem Schritt und Antwortfeld."))
            FeatureRow(symbol: "music.note", color: Self.rgb(1.0, 0.33, 0.5), title: L("Musik"),
                       text: L("Cover, Titel, Spulen und Steuerung für Spotify, Musik und fast jeden anderen Player."))
            FeatureRow(symbol: "building.2.fill", color: Self.rgb(0.25, 0.8, 0.55), title: L("Lagerhalle"),
                       text: L("Deine Agenten als Pixel-Figuren in einer Halle mit Autos, Couch und Kühlschrank. Zweimal rechte ⌘ öffnet sie."))
            FeatureRow(symbol: "tray.full.fill", color: Self.rgb(1.0, 0.68, 0.12), title: L("Ablage"),
                       text: L("Zieh Dateien auf die Notch: per AirDrop senden oder kurz ablegen und später wieder herausziehen."))
            InfoBox(symbol: "hand.raised.fill", text: L("Läuft notchai nicht, arbeiten Claude Code und Codex genau wie vorher weiter. Es verlassen keine Daten deinen Mac."))
        }
    }

    private var claudeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("notchai trägt in ~/.claude/settings.json eigene Hooks ein. So sieht die Notch, was Claude Code tut, und kann Freigaben und Fragen direkt beantworten."))
                .fixedSize(horizontal: false, vertical: true)
            ConnectionCard(agent: .claude, name: "Claude Code", color: claude,
                           installed: setup.status?.claudeInstalled ?? false, connect: setup.connectClaude)
            InfoBox(symbol: "lock.shield.fill", text: L("Vorher legt notchai eine Sicherung an. Fremde Einträge bleiben unverändert, und unter Einstellungen › Agenten lässt sich alles mit einem Knopf wieder entfernen."))
            Text(L("Ereignisse: {0} (nur melden) sowie PermissionRequest und AskUserQuestion (Freigaben und Fragen in der Notch beantworten)", Self.claudeEvents))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            message
        }
    }

    private var codexStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("notchai trägt in ~/.codex/hooks.json eigene Hooks ein. Die config.toml bleibt unberührt."))
                .fixedSize(horizontal: false, vertical: true)
            ConnectionCard(agent: .codex, name: "Codex", color: codex,
                           installed: setup.status?.codexInstalled ?? false, connect: setup.connectCodex)
            InfoBox(symbol: "terminal.fill", text: L("Codex führt neue Hooks erst aus, wenn du sie einmal bestätigt hast: Starte danach codex im Terminal und wähle bei „Hooks need review“ „Trust all and continue“."))
            Text(L("Ereignisse: {0} (nur melden) sowie PermissionRequest", Self.codexEvents))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            message
        }
    }

    @ViewBuilder
    private var message: some View {
        if let message = setup.message {
            Text(message)
                .font(.callout)
                .foregroundStyle(setup.lastActionFailed ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signalStyleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SignalStylePicker(selection: settingsStore.binding(\.signalStyle), agent: claude)
            Text(SignalStylePicker.explanation(settings.signalStyle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NotchPreviewCard(settings: settings)
            HStack {
                Text(L("Fahr mit dem Zeiger über die Vorschau oder probier es in der echten Notch aus."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                TryOutButton(action: tryOut)
            }
        }
    }

    private var appearanceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Hintergrund")
            BackgroundPicker(selection: settingsStore.binding(\.background), customHex: settings.customBackgroundHex)
            if settings.background == .custom {
                ColorPicker(L("Eigene Hintergrundfarbe"), selection: settingsStore.colorBinding(\.customBackgroundHex), supportsOpacity: false)
            }
            SectionTitle("Agentenfarben")
            HStack(alignment: .center, spacing: 20) {
                AgentColorChips(claude: claude, codex: codex)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    ColorPicker("Claude Code", selection: settingsStore.colorBinding(\.claudeColorHex), supportsOpacity: false)
                    ColorPicker("Codex", selection: settingsStore.colorBinding(\.codexColorHex), supportsOpacity: false)
                }
                .frame(width: 170)
            }
            SectionTitle("Leuchten")
            Toggle(L("Leuchten bei Signalen"), isOn: settingsStore.binding(\.glowEnabled))
            if settings.glowEnabled {
                HStack {
                    Text(L("Stärke"))
                    Slider(value: settingsStore.binding(\.glowIntensity), in: 0...1)
                }
            }
            HStack {
                Spacer()
                TryOutButton(action: tryOut)
            }
        }
    }

    private var sessionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SessionStylePicker(selection: settingsStore.binding(\.sessionViewStyle), claude: claude, codex: codex)
            Text(SessionStylePicker.explanation(settings.sessionViewStyle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            InfoBox(symbol: "bell.badge.fill", text: L("Fragt dich ein Agent etwas oder braucht eine Freigabe, meldet sich die Notch von selbst – egal welche Ansicht du wählst."))
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Den Status alle zwei Sekunden neu lesen: Die Freigabe passiert in den Systemeinstellungen.
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                PermissionCard(symbol: "accessibility", color: Self.rgb(0.25, 0.55, 1.0), title: L("Bedienungshilfen"),
                               text: L("Für zweimal rechte ⌘ (Lagerhalle) und um Antworten direkt in das Fenster einer Session zu tippen."),
                               granted: AXIsProcessTrusted(), action: OfficeHotkey.openAccessibilitySettings)
            }
            PermissionCard(symbol: "music.note", color: Self.rgb(1.0, 0.33, 0.5), title: L("Automation"),
                           text: L("Für Cover und Steuerung von Spotify und Musik. macOS fragt beim ersten Abspielen selbst nach."),
                           granted: nil, action: nil)
            InfoBox(symbol: "checkmark.shield.fill", text: L("Beides ist freiwillig. Ohne Berechtigung öffnest du die Lagerhalle über den Reiter „Büro“, und Antworten landen in der Zwischenablage."))
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(symbol: "cursorarrow.motionlines", color: Self.rgb(0.62, 0.4, 1.0), title: L("Notch aufklappen"),
                       text: L("Fahr mit der Maus an die Notch: Dort warten Musik, Sessions, die Lagerhalle und die Ablage."))
            FeatureRow(symbol: "tray.and.arrow.down.fill", color: Self.rgb(1.0, 0.68, 0.12), title: L("Dateien ablegen"),
                       text: L("Zieh eine Datei zur Notch und lass sie auf AirDrop oder der Ablage los."))
            FeatureRow(symbol: "command", color: Self.rgb(0.25, 0.8, 0.55), title: L("Lagerhalle"),
                       text: L("Zweimal kurz die rechte ⌘-Taste drücken öffnet die Halle groß."))
            FeatureRow(symbol: "gearshape.fill", color: Self.rgb(0.55, 0.55, 0.6), title: L("Einstellungen"),
                       text: L("Über das notchai-Symbol in der Menüleiste änderst du alles, was du hier gewählt hast."))
        }
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b)
    }
}

/// Titel, Beschreibung, Symbol und Farben je Schritt.
@MainActor
private struct StepInfo {
    let title: String
    let short: String
    let subtitle: String
    let symbol: String
    let colors: (Color, Color)

    init(_ step: SetupStep) {
        self = Self.of(step)
    }

    private init(title: String, short: String, subtitle: String, symbol: String, colors: (Color, Color)) {
        self.title = title
        self.short = short
        self.subtitle = subtitle
        self.symbol = symbol
        self.colors = colors
    }

    private static func of(_ step: SetupStep) -> StepInfo {
        let rgb = SetupAssistantView.rgb
        switch step {
        case .welcome:
            return StepInfo(title: L("Willkommen bei notchai"), short: "Willkommen",
                     subtitle: L("Deine Notch wird zur Steuerzentrale für Claude Code und Codex."),
                     symbol: "sparkles", colors: (rgb(1.0, 0.42, 0.62), rgb(0.62, 0.35, 1.0)))
        case .claude:
            return StepInfo(title: L("Claude Code verbinden"), short: "Claude Code",
                     subtitle: L("Damit Fragen und Freigaben direkt in der Notch landen."),
                     symbol: "terminal.fill", colors: (rgb(0.98, 0.58, 0.36), rgb(0.86, 0.38, 0.22)))
        case .codex:
            return StepInfo(title: L("Codex verbinden"), short: "Codex",
                     subtitle: L("Auch Codex meldet sich dann in der Notch."),
                     symbol: "chevron.left.forwardslash.chevron.right", colors: (rgb(0.48, 0.64, 1.0), rgb(0.25, 0.40, 0.92)))
        case .signalStyle:
            return StepInfo(title: L("So meldet sich die Notch"), short: "Signale",
                     subtitle: L("Wähle, wie Signale aussehen, und probier es gleich aus."),
                     symbol: "rectangle.topthird.inset.filled", colors: (rgb(0.32, 0.32, 0.36), rgb(0.06, 0.06, 0.07)))
        case .appearance:
            return StepInfo(title: L("Farben und Leuchten"), short: "Farben",
                     subtitle: L("Hintergrund, Agentenfarben und das Leuchten bei Signalen."),
                     symbol: "paintpalette.fill", colors: (rgb(1.0, 0.62, 0.22), rgb(0.95, 0.30, 0.45)))
        case .sessions:
            return StepInfo(title: L("Deine Sessions"), short: "Sessions",
                     subtitle: L("Wie die Notch deine laufenden Sessions zeigt."),
                     symbol: "rectangle.stack.fill", colors: (rgb(1.0, 0.66, 0.12), rgb(0.98, 0.42, 0.0)))
        case .permissions:
            return StepInfo(title: L("Berechtigungen"), short: "Berechtigungen",
                     subtitle: L("Freiwillig – für Tastenkürzel, Antworten und Musik."),
                     symbol: "lock.shield.fill", colors: (rgb(0.30, 0.82, 0.62), rgb(0.08, 0.58, 0.45)))
        case .done:
            return StepInfo(title: L("Alles bereit"), short: "Fertig",
                     subtitle: L("notchai läuft. Die Notch hört gleich auf zu leuchten – viel Spaß!"),
                     symbol: "checkmark.seal.fill", colors: (rgb(0.35, 0.85, 0.45), rgb(0.12, 0.62, 0.30)))
        }
    }
}

/// Farbige Kachel mit weißem Symbol (wie die Seitenleiste der Einstellungen); grau für spätere Schritte.
private struct StepTile: View {
    let info: StepInfo
    let size: CGFloat
    let active: Bool

    var body: some View {
        let top = active ? info.colors.0 : Color.white.opacity(0.16)
        let bottom = active ? info.colors.1 : Color.white.opacity(0.10)
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .overlay(Image(systemName: info.symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(Color.white.opacity(active ? 1 : 0.6)))
            .frame(width: size, height: size)
    }
}

/// Funktion mit farbigem Symbol, Titel und Satz.
private struct FeatureRow: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.16))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hinweis in einem dezenten Kasten.
private struct InfoBox: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.08)))
    }
}

/// Überschrift innerhalb eines Schritts.
private struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

/// Agent mit Status und Knopf zum Verbinden.
private struct ConnectionCard: View {
    let agent: AgentKind
    let name: String
    let color: Color
    let installed: Bool
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.black)
                .frame(width: 44, height: 44)
                .overlay(AgentBadge(agent: agent, color: color).scaleEffect(1.8))
                .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                StatusBadge(text: installed ? L("Verbunden") : L("Noch nicht verbunden"),
                            color: installed ? Color.green : Color.gray)
            }
            Spacer()
            if installed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.green)
            } else {
                Button(L("Verbinden"), action: connect)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(installed ? 0.5 : 0.15), lineWidth: 1))
    }
}

/// Berechtigung mit Erklärung, Status und Knopf.
private struct PermissionCard: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String
    /// `nil`: macOS fragt selbst, wenn es so weit ist.
    let granted: Bool?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let granted {
                    StatusBadge(text: granted ? L("Erlaubt") : L("Nicht erlaubt"), color: granted ? Color.green : Color.orange)
                } else {
                    StatusBadge(text: L("Fragt macOS beim ersten Abspielen"), color: Color.gray)
                }
            }
            Spacer()
            if let action, granted != true {
                Button(L("Erlauben …"), action: action)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
