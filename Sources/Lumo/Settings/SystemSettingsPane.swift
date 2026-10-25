import AppKit
import LumoCore
import SwiftUI

/// Einstellungen › System: welche Anzeigen von macOS die Notch übernimmt, ob die Einblendungen von macOS dabei
/// verschwinden, und die Berechtigungen, die das braucht.
struct SystemSettingsPane: View {
    let settingsStore: SettingsStore
    let system: SystemHUDController

    private var settings: AppSettings { settingsStore.settings }

    var body: some View {
        SettingsPage(pane: .system) {
            Section {
                SystemHUDPreviewCard()
                Toggle(L("Systemanzeigen in der Notch"), isOn: setting(\.systemHUD))
                Text(L("Lauter und leiser, heller und dunkler, Fokus, Timer und mehr erscheinen wie auf dem iPhone neben der Kamera: links das Symbol, rechts Balken, Name oder Restzeit – in den echten Farben."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    TryOutButton(action: system.preview)
                        .disabled(!settings.systemHUD)
                }
            }
            Section(L("Was die Notch zeigt")) {
                ForEach(SystemIndicatorKind.allCases, id: \.self) { kind in
                    Toggle(isOn: kindSetting(kind)) {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Lux.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.explanation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!settings.systemHUD)
                }
            }
            Section(L("Einblendungen von macOS")) {
                Toggle(L("Einblendungen von macOS ausblenden"), isOn: setting(\.suppressMacHUD))
                    .disabled(!settings.systemHUD)
                Text(L("lumo fängt die Tasten für Lautstärke, Helligkeit und Tastaturlicht ab und stellt die Werte selbst, bevor macOS sie sieht. Das graue Fenster in der Bildschirmmitte erscheint dann nicht mehr; ⌥⇧ für feine Stufen und ⌥ für die Systemeinstellungen gehen weiter. Was nicht über die Tastatur kommt (AirPods, Kontrollzentrum), zeigt die Notch zusätzlich."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                permissionRow(title: L("Bedienungshilfen"), granted: system.accessibilityTrusted,
                              text: L("Zum Abfangen der Tasten und für die Feststelltaste (Datenschutz & Sicherheit)."),
                              open: SystemHUDController.openAccessibilitySettings)
                if settings.systemHUD, settings.suppressMacHUD, system.accessibilityTrusted {
                    StatusBadge(text: system.interceptsKeys ? L("lumo fängt die Tasten ab.") : L("Der Abgriff ist gerade nicht aktiv."),
                                color: system.interceptsKeys ? .green : .orange)
                }
            }
            Section(L("Fokus, Timer und Wecker")) {
                Text(L("Den aktiven Fokus und die Timer und Wecker der Uhr-App liest lumo aus den Dateien, die macOS dafür führt. Die sind geschützt: Dafür braucht lumo den vollen Festplattenzugriff. Alles bleibt auf diesem Mac."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                permissionRow(title: L("Voller Festplattenzugriff"), granted: system.fullDiskAccess,
                              text: L("Datenschutz & Sicherheit › Voller Festplattenzugriff: lumo hinzufügen und einschalten. Danach lumo einmal neu starten."),
                              open: SystemHUDController.openFullDiskAccessSettings)
                if let problem = system.clockProblem {
                    StatusBadge(text: L("Die Uhr-Datenbank sieht anders aus als erwartet: {0}", problem), color: .orange)
                }
                if system.fullDiskAccess == true, settings.shows(.focus) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L("Fokus-Dateien"))
                            Spacer()
                            Button(L("Rohdaten kopieren"), action: system.copyFocusFiles)
                        }
                        Text(system.focusDiagnostics)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(L("Laufenden Timer stehen lassen"), isOn: setting(\.timerStaysVisible))
                    .disabled(!settings.systemHUD || !settings.shows(.timer))
            }
            Section(L("Anzeigedauer")) {
                Picker(L("Kurze Anzeigen bleiben"), selection: setting(\.systemHUDSeconds)) {
                    ForEach(AppSettings.systemHUDSecondChoices, id: \.self) { seconds in
                        Text(L("{0} s", Int(seconds))).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.systemHUD)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool?, text: String, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                switch granted {
                case .some(true): StatusBadge(text: L("Erlaubt"), color: .green)
                case .some(false): StatusBadge(text: L("Nicht erlaubt"), color: .orange)
                case .none: StatusBadge(text: L("Noch nicht geprüft"), color: .gray)
                }
                if granted != true {
                    Button(L("Systemeinstellungen öffnen"), action: open)
                }
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        settingsStore.binding(keyPath)
    }

    private func kindSetting(_ kind: SystemIndicatorKind) -> Binding<Bool> {
        Binding(
            get: { !settingsStore.settings.hudHidden.contains(kind) },
            set: { shown in
                if shown { settingsStore.settings.hudHidden.remove(kind) } else { settingsStore.settings.hudHidden.insert(kind) }
            }
        )
    }
}

/// Drei kleine Notches: Lautstärke mit Balken, Fokus mit Namen, Timer mit Restzeit.
struct SystemHUDPreviewCard: View {
    var body: some View {
        HStack(spacing: 22) {
            sample(symbol: "speaker.wave.2.fill", tint: Color(SystemTint.white)) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
                    .overlay(alignment: .leading) { Capsule().fill(Color.white).frame(width: 26, height: 3) }
            }
            sample(symbol: "briefcase.fill", tint: Color(FocusTint.rgb(named: "teal"))) {
                Text(L("Arbeiten")).font(.system(size: 7, weight: .semibold)).foregroundStyle(Color(FocusTint.rgb(named: "teal")))
            }
            sample(symbol: "timer", tint: Color(SystemTint.orange)) {
                Text("12:34").font(.system(size: 7, weight: .semibold).monospacedDigit()).foregroundStyle(Color(SystemTint.orange))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func sample<Content: View>(symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        let trailing = content()
        return MiniNotch(width: 110, height: 14) {
            HStack(spacing: 0) {
                Image(systemName: symbol).font(.system(size: 7, weight: .semibold)).foregroundStyle(tint).frame(width: 30)
                Color.clear.frame(width: 36)
                trailing.frame(width: 36, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 112, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
