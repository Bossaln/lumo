import AppKit
import NotchaiCore
import ServiceManagement
import SwiftUI

/// Einstellungsfenster im Stil der Systemeinstellungen: Seitenleiste mit farbigen Symbolen, rechts je Bereich
/// ein Kopf mit großem Symbol und darunter die Abschnitte. Alles speichert direkt in `SettingsStore`.
struct SettingsView: View {
    let settingsStore: SettingsStore
    let windowController: SettingsWindowController
    let setup: SetupController
    let updates: UpdateController
    let openAssistant: () -> Void

    @ViewState private var selection: SettingsPane? = .general
    @ViewState private var launchAtLoginMessage: String? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                sidebarHeader
                ForEach(Array(SettingsPane.groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                SettingsIcon(pane: pane, size: 22)
                            }
                            .tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 280)
        } detail: {
            detail(for: selection ?? .general)
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    /// Oben in der Seitenleiste, wie das Konto in den Systemeinstellungen: notchai mit Version.
    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("notchai")
                    .font(.system(size: 14, weight: .semibold))
                Text("Version \(updates.buildInfo.displayVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalPane
        case .updates: updatesPane
        case .notch: notchPane
        case .agents: agentsPane
        case .sessions: sessionsPane
        case .music: musicPane
        case .office: officePane
        }
    }

    // MARK: - Allgemein

    private var generalPane: some View {
        SettingsPage(pane: .general) {
            Section("Anmelden") {
                Toggle("notchai beim Anmelden starten", isOn: Binding(
                    get: { settingsStore.settings.launchAtLogin },
                    set: { launchAtLoginMessage = windowController.setLaunchAtLogin($0) }
                ))
                if let launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if SMAppService.mainApp.status == .requiresApproval {
                    Text("Erlaube notchai unter Systemeinstellungen › Allgemein › Anmeldeobjekte.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if SMAppService.mainApp.status == .notFound {
                    Text("macOS findet notchai nicht als Anmeldeobjekt.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Einrichtung") {
                LabeledContent("Einrichtungs-Assistent") {
                    Button("Öffnen …", action: openAssistant)
                }
            }
            Section("Über notchai") {
                LabeledContent("Version", value: updates.buildInfo.displayVersion)
                Text("Einstellungen werden lokal auf diesem Mac gespeichert. Die Einstellungen öffnest du jederzeit über das notchai-Symbol in der Menüleiste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Softwareupdate

    /// Update-Knopf: neuen Stand aus dem Repository holen und bauen, bzw. die neue Version über Homebrew holen.
    private var updatesPane: some View {
        SettingsPage(pane: .updates) {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: updateSymbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(updateIsProblem ? Color.orange : Color.accentColor)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updates.summary)
                            .font(.system(size: 13, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(updateNotes.enumerated()), id: \.offset) { _, note in
                            Text("• " + note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if updates.isBusy { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 4)
                HStack {
                    if FileManager.default.fileExists(atPath: UpdateController.logURL.path) {
                        Button("Protokoll") { NSWorkspace.shared.open(UpdateController.logURL) }
                    }
                    Spacer()
                    Button("Nach Updates suchen") { Task { await updates.check() } }
                        .disabled(updates.isBusy)
                    if updates.canInstall {
                        Button("Jetzt aktualisieren") { Task { await updates.install() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(updates.isBusy)
                    }
                }
            }
            Section {
                Toggle("Automatisch nach Updates suchen", isOn: setting(\.checkForUpdates))
                LabeledContent("Quelle") {
                    Text(updates.sourceDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Neue Commits bzw. die Punkte der Versionshinweise.
    private var updateNotes: [String] {
        switch updates.state {
        case .available(let offer): Array(offer.subjects.prefix(6))
        case .releaseAvailable(let offer): offer.notes
        default: []
        }
    }

    private var updateSymbol: String {
        switch updates.state {
        case .available, .releaseAvailable: "arrow.down.circle.fill"
        case .blocked, .failed: "exclamationmark.triangle.fill"
        default: "checkmark.seal.fill"
        }
    }

    private var updateIsProblem: Bool {
        switch updates.state {
        case .blocked, .failed: true
        default: false
        }
    }

    // MARK: - Notch

    private var notchPane: some View {
        let settings = settingsStore.settings
        return SettingsPage(pane: .notch) {
            Section {
                NotchPreviewCard(settings: settings)
            }
            Section("Signalform") {
                ChoiceCards(options: [(SignalStyle.island, "Island"), (.banner, "Banner"), (.vertical, "Vertikal")],
                            selection: setting(\.signalStyle)) { style in
                    signalThumbnail(style)
                }
            }
            Section("Darstellung") {
                Picker("Hintergrund", selection: setting(\.background)) {
                    Text("Schwarz").tag(BackgroundStyle.black)
                    Text("Dunkelgrau").tag(BackgroundStyle.darkGray)
                    Text("Eigene Farbe").tag(BackgroundStyle.custom)
                }
                if settings.background == .custom {
                    ColorPicker("Eigene Hintergrundfarbe", selection: colorSetting(\.customBackgroundHex), supportsOpacity: false)
                }
                ColorPicker("Farbe von Claude Code", selection: colorSetting(\.claudeColorHex), supportsOpacity: false)
                ColorPicker("Farbe von Codex", selection: colorSetting(\.codexColorHex), supportsOpacity: false)
            }
            Section("Effekte") {
                Toggle("Leuchten bei Signalen", isOn: setting(\.glowEnabled))
                if settings.glowEnabled {
                    LabeledContent("Stärke") {
                        HStack {
                            Slider(value: setting(\.glowIntensity), in: 0...1)
                            Text(settings.glowIntensity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                LabeledContent("Gummi-Effekt") {
                    HStack {
                        Slider(value: setting(\.notchBounce), in: 0...1, step: 0.05)
                        Text(settings.notchBounce == 0 ? "Aus" : settings.notchBounce.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Töne", isOn: setting(\.soundsEnabled))
            }
            Section("Bedienung") {
                Picker("Beim Aufklappen zeigen", selection: setting(\.panelOpenBehavior)) {
                    Text("Wo gerade etwas passiert").tag(PanelOpenBehavior.activity)
                    Text("Zuletzt gewählten Reiter").tag(PanelOpenBehavior.lastUsed)
                }
                if settings.panelOpenBehavior == .activity {
                    Text("Wartet Claude Code oder Codex auf dich, öffnen sich die Sessions. Sonst öffnet laufende Musik den Reiter „Musik“, arbeitende Agenten die Sessions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Hover-Verzögerung") {
                    HStack {
                        Slider(value: integerSetting(\.hoverDelayMs), in: 0...1000, step: 25)
                        Text("\(settings.hoverDelayMs) ms")
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                LabeledContent("Island-Breite je Seite") {
                    HStack {
                        Slider(value: setting(\.islandSideWidth), in: AppSettings.islandSideWidthRange, step: 5)
                        Text("\(Int(settings.islandSideWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Miniatur je Signalform für die Auswahlkarten.
    @ViewBuilder
    private func signalThumbnail(_ style: SignalStyle) -> some View {
        let agent = Color(hex: settingsStore.settings.claudeColorHex)
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

    // MARK: - Agenten

    /// Hooks von Claude Code und Codex: Status, neu einrichten, alles entfernen.
    private var agentsPane: some View {
        SettingsPage(pane: .agents) {
            Section("Verbindung") {
                LabeledContent("Claude Code") { connection(setup.status?.claudeInstalled) }
                LabeledContent("Codex") { connection(setup.status?.codexInstalled) }
                if let message = setup.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(setup.lastActionFailed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                HStack {
                    Button("Einrichtung …", action: openAssistant)
                    Button("Neu einrichten") {
                        setup.connectClaude()
                        setup.connectCodex()
                    }
                    Spacer()
                    Button("Sicherungen zeigen") { setup.showBackups() }
                    Button("Alles entfernen") { setup.removeAll() }
                }
            }
        }
        .onAppear { setup.refresh() }
    }

    private func connection(_ installed: Bool?) -> StatusBadge {
        switch installed {
        case .some(true): StatusBadge(text: "Verbunden", color: Color.green)
        case .some(false): StatusBadge(text: "Nicht verbunden", color: Color.orange)
        case .none: StatusBadge(text: "Unbekannt", color: Color.gray)
        }
    }

    // MARK: - Sessions

    private var sessionsPane: some View {
        SettingsPage(pane: .sessions) {
            Section("Ansicht") {
                ChoiceCards(options: [(SessionViewStyle.list, "Liste"), (.circles, "Kreise")],
                            selection: setting(\.sessionViewStyle)) { style in
                    sessionThumbnail(style)
                }
                Picker("Titel", selection: setting(\.sessionTitleSource)) {
                    Text("Letzte Aufgabe").tag(SessionTitleSource.lastPrompt)
                    Text("Session-Titel bevorzugen").tag(SessionTitleSource.sessionTitle)
                }
                Toggle("Claude Code beobachten", isOn: setting(\.watchClaude))
                Toggle("Codex beobachten", isOn: setting(\.watchCodex))
            }
            Section("Signale") {
                Toggle("Bei Fragen", isOn: setting(\.signalOnQuestion))
                Toggle("Bei Freigaben", isOn: setting(\.signalOnPermission))
                Toggle("Bei Abschluss", isOn: setting(\.signalOnDone))
                Toggle("Bei Fehlern", isOn: setting(\.signalOnError))
                LabeledContent("Freigabe-Wartezeit") {
                    HStack {
                        Slider(value: integerSetting(\.approvalTimeoutSeconds), in: 5...125, step: 5)
                        Text("\(settingsStore.settings.approvalTimeoutSeconds) s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            Section("Antworten") {
                Toggle("Antworten an Claude automatisch eintippen", isOn: setting(\.autoSendClaudeReplies))
            }
        }
    }

    @ViewBuilder
    private func sessionThumbnail(_ style: SessionViewStyle) -> some View {
        let claude = Color(hex: settingsStore.settings.claudeColorHex)
        let codex = Color(hex: settingsStore.settings.codexColorHex)
        switch style {
        case .list:
            MiniNotch(width: 92, height: 50) {
                VStack(alignment: .leading, spacing: 5) {
                    Spacer().frame(height: 8)
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 4) {
                            Circle().fill(row == 1 ? codex : claude).frame(width: 5, height: 5)
                            Capsule().fill(Color.white.opacity(0.55)).frame(width: row == 2 ? 38 : 54, height: 3)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .circles:
            MiniNotch(width: 92, height: 12) {
                HStack(spacing: 3) {
                    Circle().fill(claude).frame(width: 6, height: 6)
                    Circle().fill(codex).frame(width: 6, height: 6)
                    Spacer()
                    Circle().fill(claude.opacity(0.7)).frame(width: 6, height: 6)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Musik

    private var musicPane: some View {
        let settings = settingsStore.settings
        return SettingsPage(pane: .music) {
            Section {
                MusicPreviewCard(settings: settings)
                Toggle("Musikanzeige", isOn: setting(\.musicEnabled))
            }
            Section("Was zeigt die Notch?") {
                ChoiceCards(options: [(MusicSourceMode.musicServices, "Nur Musikdienste"),
                                      (.allPlayers, "Alles, was abspielt")],
                            selection: setting(\.musicSourceMode)) { mode in
                    sourceThumbnail(mode)
                }
                Text(sourceModeHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.musicSourceMode == .musicServices {
                    Toggle("Musik im Browser erkennen (YouTube Music, Spotify Web …)", isOn: setting(\.musicBrowserMusic))
                    Toggle("Podcasts zeigen", isOn: setting(\.musicIncludePodcasts))
                }
            }
            Section("Darstellung") {
                Toggle("Eingeklappt neben der Kamera (Cover und Balken)", isOn: setting(\.musicCompactView))
                Toggle("Hintergrund in den Farben des Covers", isOn: setting(\.musicArtworkBackground))
                Picker("Cover beim Titelwechsel", selection: setting(\.musicCoverTransition)) {
                    Text("Weich überblenden").tag(CoverTransitionStyle.blur)
                    Text("In Skip-Richtung umklappen").tag(CoverTransitionStyle.flip)
                }
                Toggle("Leuchten in der Farbe des Covers", isOn: setting(\.musicCoverGlow))
                Toggle("Cover laden", isOn: setting(\.musicLoadArtwork))
                Text("Cover kommen per AppleScript aus Spotify und Musik; beim ersten Mal fragt macOS, ob notchai die App steuern darf. Spotify-Cover lädt notchai von Spotifys Bildserver.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            knownPlayersSection
        }
    }

    private var sourceModeHint: String {
        switch settingsStore.settings.musicSourceMode {
        case .musicServices:
            "Spotify, Apple Music, TIDAL und Co. Ein YouTube-Video im Browser erscheint nicht; Musik im Browser erkennt notchai daran, dass die Seite ein Album meldet."
        case .allPlayers:
            "Alles, was macOS als „Jetzt läuft“ meldet, auch Videos im Browser."
        }
    }

    @ViewBuilder
    private func sourceThumbnail(_ mode: MusicSourceMode) -> some View {
        switch mode {
        case .musicServices:
            ZStack {
                LinearGradient(colors: [Color(.sRGB, red: 1.0, green: 0.36, blue: 0.5),
                                        Color(.sRGB, red: 0.55, green: 0.18, blue: 0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        case .allPlayers:
            ZStack {
                LinearGradient(colors: [Color(.sRGB, red: 0.25, green: 0.55, blue: 1.0),
                                        Color(.sRGB, red: 0.2, green: 0.25, blue: 0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Image(systemName: "play.rectangle.fill")
                    Image(systemName: "mic.fill")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
            }
        }
    }

    /// Jede bisher gesehene App mit ihrer Art und einer eigenen Regel, die dem Modus vorgeht.
    private var knownPlayersSection: some View {
        let settings = settingsStore.settings
        let players = settings.musicKnownSources
            .map { (key: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Section("Erkannte Player") {
            if players.isEmpty {
                Text("Noch keine. Sobald etwas abspielt, erscheint die App hier.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(players, id: \.key) { player in
                    let kind = PlayerCatalog.kind(of: PlayerSource(bundleId: player.key.hasPrefix("name:") ? nil : player.key,
                                                                   name: player.name))
                    Picker(selection: ruleSetting(player.key)) {
                        Text("Automatisch").tag(MusicSourceRule.automatic)
                        Text("Immer zeigen").tag(MusicSourceRule.always)
                        Text("Nie zeigen").tag(MusicSourceRule.never)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                            Text("\(kind.label) · automatisch: \(MusicFilter.automaticSummary(for: kind, settings: settings))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Liste leeren") {
                        settingsStore.settings.musicKnownSources = [:]
                        settingsStore.settings.musicSourceRules = [:]
                    }
                    .help("Entfernt alle erkannten Player samt ihrer Regeln.")
                }
            }
        }
    }

    private func ruleSetting(_ key: String) -> Binding<MusicSourceRule> {
        Binding(
            get: { settingsStore.settings.musicSourceRules[key] ?? .automatic },
            set: { settingsStore.settings.musicSourceRules[key] = $0 == .automatic ? nil : $0 }
        )
    }

    // MARK: - Büro

    private var officePane: some View {
        SettingsPage(pane: .office) {
            Section("Pixel-Büro") {
                Toggle("Büro aktivieren", isOn: setting(\.officeEnabled))
                LabeledContent("Größe") {
                    HStack {
                        Slider(value: setting(\.officeScale), in: 0.5...2, step: 0.1)
                        Text(settingsStore.settings.officeScale, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Beleuchtung", selection: setting(\.officeLighting)) {
                    Text("Echte Sonne").tag(OfficeLighting.realSun)
                    Text("Fester Tag").tag(OfficeLighting.fixedDay)
                    Text("Feste Nacht").tag(OfficeLighting.fixedNight)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Büro-Ton", isOn: setting(\.officeSound))
                        .disabled(true)
                    Text("Lo-Fi-Musik für die Halle kommt später.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Tastenkürzel") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Zweimal rechte ⌘ öffnet das Büro", isOn: setting(\.officeHotkey))
                    Text("Geht auch, wenn eine andere App vorn ist. Ohne Kürzel öffnet ein Klick im Reiter „Büro“ "
                        + "oder „Büro öffnen“ im Menü die Halle groß.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if settingsStore.settings.officeHotkey && !OfficeHotkey.isTrusted {
                    LabeledContent("Bedienungshilfen") {
                        Button("Erlauben …") { OfficeHotkey.openAccessibilitySettings() }
                    }
                    Text("Damit notchai die ⌘-Taste in anderen Apps bemerkt, braucht es die Berechtigung "
                        + "„Bedienungshilfen“ (Datenschutz & Sicherheit).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Standort für den Sonnenstand (optional)") {
                CoordinateField(kind: .latitude, settingsStore: settingsStore)
                CoordinateField(kind: .longitude, settingsStore: settingsStore)
            }
        }
    }

    // MARK: - Bindungen

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { settingsStore.settings[keyPath: keyPath] = $0 }
        )
    }

    private func integerSetting(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Double> {
        Binding(
            get: { Double(settingsStore.settings[keyPath: keyPath]) },
            set: { settingsStore.settings[keyPath: keyPath] = Int($0.rounded()) }
        )
    }

    private func colorSetting(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: settingsStore.settings[keyPath: keyPath]) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                settingsStore.settings[keyPath: keyPath] = ColorHex.format(RGB(
                    r: Double(rgb.redComponent),
                    g: Double(rgb.greenComponent),
                    b: Double(rgb.blueComponent)
                ))
            }
        )
    }
}

/// Breiten- oder Längengrad mit eigenem Textpuffer: Übernommen wird erst bei Return oder beim Verlassen
/// des Felds. Ungültiges zeigt einen Hinweis und lässt den gespeicherten Wert stehen.
private struct CoordinateField: View {
    let kind: CoordinateInput
    let settingsStore: SettingsStore

    @ViewState private var text = ""
    @ViewState private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $text, prompt: Text(prompt))
                .focused($isFocused)
                .onSubmit(commit)
            if isInvalid {
                Text(kind.invalidHint)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onAppear {
            text = CoordinateInput.format(settingsStore.settings[keyPath: keyPath])
            isInvalid = false
        }
        .onDisappear(perform: commit)
    }

    private var label: String {
        switch kind {
        case .latitude: "Breitengrad"
        case .longitude: "Längengrad"
        }
    }

    private var prompt: String {
        switch kind {
        case .latitude: "z. B. 52,52"
        case .longitude: "z. B. 13,40"
        }
    }

    private var keyPath: WritableKeyPath<AppSettings, Double?> {
        switch kind {
        case .latitude: \.officeLatitude
        case .longitude: \.officeLongitude
        }
    }

    private func commit() {
        let newValue: Double?
        switch kind.parse(text) {
        case .invalid:
            isInvalid = true
            return
        case .empty:
            newValue = nil
        case .value(let value):
            newValue = value
        }
        isInvalid = false
        text = CoordinateInput.format(newValue)
        if settingsStore.settings[keyPath: keyPath] != newValue {
            settingsStore.settings[keyPath: keyPath] = newValue
        }
    }
}
