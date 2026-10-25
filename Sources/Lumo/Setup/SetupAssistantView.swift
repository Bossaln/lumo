import AppKit
import ApplicationServices
import LumoCore
import SwiftUI

/// Einrichtungs-Assistent, filmisch: ein Schritt pro Bild, mittig ein großes Motiv (die Notch selbst oder das
/// Symbol des Schritts), darunter Titel, Inhalt und unten Fortschrittspunkte mit der Hauptaktion. Hooks verbinden, Design wählen (mit „In der Notch ausprobieren“),
/// Berechtigungen. Jeder Schritt lässt sich überspringen; alles ist später in den Einstellungen änderbar.
struct SetupAssistantView: View {
    let setup: SetupController
    let settingsStore: SettingsStore
    /// Zeigt ein Beispiel-Signal in der echten Notch.
    let tryOut: () -> Void
    let finish: () -> Void

    @ViewState private var step: SetupStep = .language

    /// Hook-Ereignisse, die lumo nur meldet (ohne die, auf die es antwortet).
    private static let claudeEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Notification, Stop, StopFailure, SubagentStart, SubagentStop"
    private static let codexEvents = "SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop"

    var body: some View {
        ZStack {
            LuxBackdrop(colors: [claude, codex, StepInfo(step).colors.0], intensity: 0.9)
                .animation(.easeInOut(duration: 1.0), value: step)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 26) {
                        SetupHero(step: step, claude: claude, codex: codex)
                        header
                        content
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 54)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.97)),
                        removal: .opacity.combined(with: .scale(scale: 1.02))))
                }
                .scrollIndicators(.never)
                footer
                    .padding(.horizontal, 32)
                    .padding(.vertical, 22)
            }
        }
        .frame(width: 880, height: 660)
        .background(Lux.background)
        .luxControls()
        // Neue Sprache: alles neu aufbauen, damit jeder Text sie zeigt.
        .id(settingsStore.settings.language)
        .onAppear { setup.refresh() }
    }

    private var settings: AppSettings { settingsStore.settings }
    private var claude: Color { Color(hex: settings.claudeColorHex) }
    private var codex: Color { Color(hex: settings.codexColorHex) }

    private func go(to target: SetupStep) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { step = target }
    }

    // MARK: - Kopf und Fuß

    private var header: some View {
        let info = StepInfo(step)
        return VStack(spacing: 10) {
            Text(info.title)
                .font(.system(size: 36, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Lux.primary)
            Text(info.subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Lux.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
        }
    }

    /// Links zurück, in der Mitte die Punkte (anklickbar), rechts die Hauptaktion.
    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 18) {
                if step == .language {
                    quietButton(L("Später")) { finish() }
                } else if let previous = step.previous, step != .done {
                    quietButton(L("Zurück")) { go(to: previous) }
                }
                if step == .claude || step == .codex {
                    quietButton(L("Überspringen")) { advance() }
                }
            }
            .frame(width: 220, alignment: .leading)
            Spacer(minLength: 0)
            progressDots
            Spacer(minLength: 0)
            primaryButton
                .buttonStyle(LuxButtonStyle(prominent: true, large: true))
                .keyboardShortcut(.defaultAction)
                .frame(width: 220, alignment: .trailing)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(SetupStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? Color.white : Color.white.opacity(item.rawValue < step.rawValue ? 0.5 : 0.18))
                    .frame(width: item == step ? 22 : 6, height: 6)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { go(to: item) }
            }
        }
        .animation(Lux.spring, value: step)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Lux.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .language: languageStep
        case .welcome: welcome
        case .claude: claudeStep
        case .codex: codexStep
        case .signalStyle: signalStyleStep
        case .appearance: appearanceStep
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    /// Zwei große Karten; ein Klick wechselt sofort, auch alle weiteren Schritte erscheinen dann in der Sprache.
    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    LanguageCard(language: language, selected: Localization.language == language) {
                        LanguageSwitch.set(language, in: settingsStore)
                    }
                }
            }
            InfoBox(symbol: "globe", text: L("Du kannst die Sprache jederzeit unter Einstellungen › Allgemein ändern."))
        }
    }

    private var welcome: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .top), GridItem(.flexible(), alignment: .top)],
                  alignment: .leading, spacing: 20) {
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
            InfoBox(symbol: "hand.raised.fill", text: L("Läuft lumo nicht, arbeiten Claude Code und Codex genau wie vorher weiter. Es verlassen keine Daten deinen Mac."))
        }
    }

    private var claudeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("lumo trägt in ~/.claude/settings.json eigene Hooks ein. So sieht die Notch, was Claude Code tut, und kann Freigaben und Fragen direkt beantworten."))
                .fixedSize(horizontal: false, vertical: true)
            ConnectionCard(agent: .claude, name: "Claude Code", color: claude,
                           installed: setup.status?.claudeInstalled ?? false, connect: setup.connectClaude)
            InfoBox(symbol: "lock.shield.fill", text: L("Vorher legt lumo eine Sicherung an. Fremde Einträge bleiben unverändert, und unter Einstellungen › Agenten lässt sich alles mit einem Knopf wieder entfernen."))
            Text(L("Ereignisse: {0} (nur melden) sowie PermissionRequest und AskUserQuestion (Freigaben und Fragen in der Notch beantworten)", Self.claudeEvents))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            message
        }
    }

    private var codexStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("lumo trägt in ~/.codex/hooks.json eigene Hooks ein. Die config.toml bleibt unberührt."))
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

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Den Status alle zwei Sekunden neu zeigen: Die Freigabe passiert in den Systemeinstellungen
            // (geprüft wird im Hintergrund, `DoubleTapHotkeys.isTrusted`).
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                PermissionCard(symbol: "accessibility", color: Self.rgb(0.25, 0.55, 1.0), title: L("Bedienungshilfen"),
                               text: L("Für zweimal rechte ⌘ (Lagerhalle), zweimal ⌃ (Schnellnotiz) und um Antworten direkt in das Fenster einer Session zu tippen."),
                               granted: DoubleTapHotkeys.isTrusted, action: DoubleTapHotkeys.openAccessibilitySettings)
            }
            PermissionCard(symbol: "music.note", color: Self.rgb(1.0, 0.33, 0.5), title: L("Automation"),
                           text: L("Für Cover und Steuerung von Spotify und Musik. macOS fragt beim ersten Abspielen selbst nach."),
                           granted: nil, action: nil)
            PermissionCard(symbol: "waveform", color: Self.rgb(0.2, 0.75, 0.6), title: L("Systemaudio"),
                           text: L("Damit die Balken neben der Kamera echt zur Musik tanzen. lumo rechnet nur die Höhen aus; nichts wird gespeichert."),
                           granted: nil, action: nil)
            PermissionCard(symbol: "externaldrive.fill", color: Self.rgb(0.95, 0.6, 0.2), title: L("Voller Festplattenzugriff"),
                           text: L("Für Fokus, Timer und Wecker in der Notch: lumo liest die Dateien, die macOS dafür führt. Freiwillig; alles andere geht auch ohne."),
                           granted: nil, action: SystemHUDController.openFullDiskAccessSettings, pending: L("Freiwillig, in den Systemeinstellungen"))
            InfoBox(symbol: "checkmark.shield.fill", text: L("Alles ist freiwillig. Ohne Berechtigung öffnest du die Lagerhalle über den Reiter „Büro“, Antworten landen in der Zwischenablage, und die Balken tanzen animiert."))
        }
    }

    private var doneStep: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .top), GridItem(.flexible(), alignment: .top)],
                  alignment: .leading, spacing: 20) {
            FeatureRow(symbol: "cursorarrow.motionlines", color: Self.rgb(0.62, 0.4, 1.0), title: L("Notch aufklappen"),
                       text: L("Fahr mit der Maus an die Notch: Dort warten Musik, Sessions, die Lagerhalle und die Ablage."))
            FeatureRow(symbol: "tray.and.arrow.down.fill", color: Self.rgb(1.0, 0.68, 0.12), title: L("Dateien ablegen"),
                       text: L("Zieh eine Datei zur Notch und lass sie auf AirDrop oder der Ablage los."))
            FeatureRow(symbol: "command", color: Self.rgb(0.25, 0.8, 0.55), title: L("Lagerhalle"),
                       text: L("Zweimal kurz die rechte ⌘-Taste drücken öffnet die Halle groß."))
            FeatureRow(symbol: "note.text", color: Self.rgb(1.0, 0.8, 0.2), title: L("Schnellnotiz"),
                       text: L("Zweimal ⌃ drücken, schreiben, ↩ – die Notiz landet im Reiter „Notizen“."))
            FeatureRow(symbol: "gearshape.fill", color: Self.rgb(0.55, 0.55, 0.6), title: L("Einstellungen"),
                       text: L("Über das lumo-Symbol in der Menüleiste änderst du alles, was du hier gewählt hast."))
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
        case .language:
            return StepInfo(title: L("Sprache"), short: L("Sprache"),
                     subtitle: L("In welcher Sprache soll lumo mit dir sprechen?"),
                     symbol: "globe", colors: (rgb(0.30, 0.70, 1.0), rgb(0.20, 0.38, 0.95)))
        case .welcome:
            return StepInfo(title: L("Willkommen bei lumo"), short: L("Willkommen"),
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
            return StepInfo(title: L("So meldet sich die Notch"), short: L("Signale"),
                     subtitle: L("Wähle, wie Signale aussehen, und probier es gleich aus."),
                     symbol: "rectangle.topthird.inset.filled", colors: (rgb(0.32, 0.32, 0.36), rgb(0.06, 0.06, 0.07)))
        case .appearance:
            return StepInfo(title: L("Farben und Leuchten"), short: L("Farben"),
                     subtitle: L("Hintergrund, Agentenfarben und das Leuchten bei Signalen."),
                     symbol: "paintpalette.fill", colors: (rgb(1.0, 0.62, 0.22), rgb(0.95, 0.30, 0.45)))
        case .permissions:
            return StepInfo(title: L("Berechtigungen"), short: L("Berechtigungen"),
                     subtitle: L("Freiwillig – für Tastenkürzel, Antworten und Musik."),
                     symbol: "lock.shield.fill", colors: (rgb(0.30, 0.82, 0.62), rgb(0.08, 0.58, 0.45)))
        case .done:
            return StepInfo(title: L("Alles bereit"), short: L("Fertig"),
                     subtitle: L("lumo läuft. Die Notch hört gleich auf zu leuchten – viel Spaß!"),
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Lux.primary)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Lux.secondary)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Lux.secondary)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Lux.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Lux.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Lux.hairline, lineWidth: 1))
    }
}

/// Überschrift innerhalb eines Schritts.
private struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(L(text).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Lux.tertiary)
            .padding(.top, 8)
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
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).fill(Lux.card))
        .overlay(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).strokeBorder(installed ? color.opacity(0.6) : Lux.hairline, lineWidth: 1))
        .shadow(color: color.opacity(installed ? 0.25 : 0), radius: 24, y: 8)
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
    /// Hinweis statt des Status, wenn macOS nicht selbst fragt (`granted == nil`).
    var pending: String? = nil

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
                    StatusBadge(text: pending ?? L("Fragt macOS beim ersten Abspielen"), color: Color.gray)
                }
            }
            Spacer()
            if let action, granted != true {
                Button(L("Erlauben …"), action: action)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).fill(Lux.card))
        .overlay(RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous).strokeBorder(Lux.hairline, lineWidth: 1))
    }
}

/// Karte für eine Sprache: Kürzel, Name und ein Gruß in der Sprache selbst.
private struct LanguageCard: View {
    let language: AppLanguage
    let selected: Bool
    let choose: () -> Void

    @ViewState private var hovering = false

    /// Der Gruß steht immer in der Sprache der Karte, nicht in der gerade eingestellten.
    private var greeting: String {
        switch language {
        case .german: "Hallo! Die Notch spricht Deutsch."
        case .english: "Hi! The notch speaks English."
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Lux.cardRadius, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(language.rawValue.uppercased())
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(LinearGradient(
                            colors: language == .german ? [SetupAssistantView.rgb(1.0, 0.55, 0.25), SetupAssistantView.rgb(0.92, 0.25, 0.30)]
                                : [SetupAssistantView.rgb(0.30, 0.70, 1.0), SetupAssistantView.rgb(0.20, 0.38, 0.95)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Color.white : Lux.tertiary)
                }
                Text(language.nativeName)
                    .font(.system(size: 18, weight: .bold))
                Text(greeting)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? Lux.cardHover : hovering ? Lux.cardHover : Lux.card))
            .overlay(shape.strokeBorder(selected ? Color.white.opacity(0.85) : Lux.hairline, lineWidth: selected ? 1.5 : 1))
            .shadow(color: Color.white.opacity(selected ? 0.12 : 0), radius: 20)
            .scaleEffect(hovering && !selected ? 1.02 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { hovering = inside }
        }
    }
}

/// Motiv über dem Titel. Zur Begrüßung und am Ende die Notch selbst, die atmet und Signale zeigt; sonst das Symbol
/// des Schritts, das leicht schwebt und in seinen Farben leuchtet.
private struct SetupHero: View {
    let step: SetupStep
    let claude: Color
    let codex: Color

    var body: some View {
        switch step {
        case .welcome, .done:
            CinematicNotch(claude: claude, codex: codex, finished: step == .done)
        default:
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let info = StepInfo(step)
                ZStack {
                    Circle()
                        .fill(info.colors.0.opacity(0.35))
                        .frame(width: 150, height: 150)
                        .blur(radius: 40)
                        .scaleEffect(1 + 0.06 * sin(t * 1.3))
                    StepTile(info: info, size: 84, active: true)
                        .shadow(color: info.colors.1.opacity(0.6), radius: 24, y: 10)
                        .offset(y: 4 * sin(t * 1.1))
                }
                .frame(height: 120)
            }
        }
    }
}

/// Die Notch als Hauptdarsteller: eine große schwarze Form oben am Rand eines angedeuteten Bildschirms. Sie klappt im
/// Wechsel auf und zu, leuchtet abwechselnd in den Agentenfarben und zeigt kurze Signale.
private struct CinematicNotch: View {
    let claude: Color
    let codex: Color
    let finished: Bool

    /// Länge eines Signals im Wechsel.
    private static let period: Double = 3.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let index = Int(t / Self.period) % 2
            let phase = t.truncatingRemainder(dividingBy: Self.period) / Self.period
            // Auf, kurz stehen, wieder zu.
            let open = min(1, max(0, phase < 0.5 ? phase * 5 : (0.9 - phase) * 5))
            let color = index == 0 ? claude : codex
            let width = 150 + 210 * open
            let height = 34 + 58 * open
            ZStack(alignment: .top) {
                // Angedeuteter Bildschirmrand.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Lux.hairline, lineWidth: 1))
                    .frame(width: 520, height: 150)
                let shape = NotchShape(bottomRadius: 12 + 14 * open, topCornerRadius: 6)
                shape
                    .fill(Color.black)
                    .frame(width: width, height: height)
                    .shadow(color: color.opacity(0.75 * open), radius: 22)
                    .shadow(color: color.opacity(0.4 * open), radius: 4)
                    .overlay(alignment: .bottom) {
                        signal(index: index, color: color)
                            .opacity(max(0, open * 1.6 - 0.6))
                            .padding(.bottom, 12)
                    }
                    .clipShape(shape)
            }
            .frame(width: 520, height: 150)
        }
    }

    private func signal(index: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).shadow(color: color, radius: 4)
            Text(text(index))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            Capsule().fill(color).frame(width: 54, height: 20)
                .overlay(Text(index == 0 && !finished ? L("Erlauben") : "✓")
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Color.black))
        }
        .padding(.horizontal, 20)
        .frame(width: 360)
    }

    private func text(_ index: Int) -> String {
        switch (index, finished) {
        case (0, false): L("Claude möchte ausführen: npm test")
        case (_, true): L("Alles bereit")
        default: L("Codex ist fertig")
        }
    }
}
