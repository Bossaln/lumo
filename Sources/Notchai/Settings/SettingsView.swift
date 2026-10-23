import AppKit
import NotchaiCore
import ServiceManagement
import SwiftUI

/// Einstellungsfenster im Stil der Systemeinstellungen: Seitenleiste mit farbigen Symbolen, rechts je Bereich
/// ein Kopf mit großem Symbol und darunter die Abschnitte. Alles speichert direkt in `SettingsStore`.
struct SettingsView: View {
    let settingsStore: SettingsStore
    let shelfStore: ShelfStore
    let noteStore: NoteStore
    let windowController: SettingsWindowController
    let setup: SetupController
    let updates: UpdateController
    let openAssistant: () -> Void
    let developer: DeveloperTools
    /// Zeigt ein Beispiel-Signal in der echten Notch.
    let tryOut: () -> Void
    let music: MusicSettingsActions

    @ViewState private var selection: SettingsPane? = .general
    @ViewState private var launchAtLoginMessage: String? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                sidebarHeader
                ForEach(Array(SettingsPane.groups(developer: settingsStore.settings.developerOptions).enumerated()),
                        id: \.offset) { _, group in
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
        // Neue Sprache: alles neu aufbauen, damit jeder Text sie zeigt.
        .id(settingsStore.settings.language)
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
                Text(L("Version {0}", updates.buildInfo.displayVersion))
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
        case .shelf: shelfPane
        case .notes: notesPane
        case .developer:
            // Wird die Seite ausgeschaltet, während sie offen ist, geht es zurück zu „Allgemein“.
            if settingsStore.settings.developerOptions { developerPane } else { generalPane }
        }
    }

    // MARK: - Allgemein

    private var generalPane: some View {
        SettingsPage(pane: .general) {
            Section(L("Sprache")) {
                Picker(L("Sprache"), selection: Binding(
                    get: { Localization.language },
                    set: { LanguageSwitch.set($0, in: settingsStore) }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(L("Anmelden")) {
                Toggle(L("notchai beim Anmelden starten"), isOn: Binding(
                    get: { settingsStore.settings.launchAtLogin },
                    set: { launchAtLoginMessage = windowController.setLaunchAtLogin($0) }
                ))
                if let launchAtLoginMessage {
                    Text(launchAtLoginMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if windowController.loginItemStatus == .requiresApproval {
                    Text(L("Erlaube notchai unter Systemeinstellungen › Allgemein › Anmeldeobjekte."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if windowController.loginItemStatus == .notFound {
                    Text(L("macOS findet notchai nicht als Anmeldeobjekt."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Einrichtung")) {
                LabeledContent(L("Einrichtungs-Assistent")) {
                    Button(L("Öffnen …"), action: openAssistant)
                }
            }
            Section(L("Entwickler")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Entwickleroptionen"), isOn: setting(\.developerOptions))
                    Text(L("Blendet in der Seitenleiste die Seite „Entwickler“ ein: Test-Signale, Rohdaten und Zurücksetzen."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Über notchai")) {
                LabeledContent(L("Version"), value: updates.buildInfo.displayVersion)
                Text(L("Einstellungen werden lokal auf diesem Mac gespeichert. Die Einstellungen öffnest du jederzeit über das notchai-Symbol in der Menüleiste."))
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
                        Button(L("Protokoll")) { NSWorkspace.shared.open(UpdateController.logURL) }
                    }
                    Spacer()
                    Button(L("Nach Updates suchen")) { Task { await updates.check() } }
                        .disabled(updates.isBusy)
                    if updates.canInstall {
                        Button(L("Jetzt aktualisieren")) { Task { await updates.install() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(updates.isBusy)
                    }
                }
            }
            Section {
                Toggle(L("Automatisch nach Updates suchen"), isOn: setting(\.checkForUpdates))
                LabeledContent(L("Quelle")) {
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
            Section(L("Signalform")) {
                SignalStylePicker(selection: setting(\.signalStyle), agent: Color(hex: settings.claudeColorHex))
                Text(SignalStylePicker.explanation(settings.signalStyle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    TryOutButton(action: tryOut)
                }
            }
            Section(L("Hintergrund")) {
                BackgroundPicker(selection: setting(\.background), customHex: settings.customBackgroundHex)
                if settings.background == .custom {
                    ColorPicker(L("Eigene Hintergrundfarbe"), selection: colorSetting(\.customBackgroundHex), supportsOpacity: false)
                }
            }
            Section(L("Agentenfarben")) {
                HStack {
                    Spacer()
                    AgentColorChips(claude: Color(hex: settings.claudeColorHex), codex: Color(hex: settings.codexColorHex))
                    Spacer()
                }
                .padding(.vertical, 6)
                ColorPicker(L("Farbe von Claude Code"), selection: colorSetting(\.claudeColorHex), supportsOpacity: false)
                ColorPicker(L("Farbe von Codex"), selection: colorSetting(\.codexColorHex), supportsOpacity: false)
            }
            Section(L("Effekte")) {
                Toggle(L("Leuchten bei Signalen"), isOn: setting(\.glowEnabled))
                if settings.glowEnabled {
                    LabeledContent(L("Stärke")) {
                        HStack {
                            Slider(value: setting(\.glowIntensity), in: 0...1)
                            Text(settings.glowIntensity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                LabeledContent(L("Gummi-Effekt")) {
                    HStack {
                        Slider(value: setting(\.notchBounce), in: 0...1, step: 0.05)
                        Text(settings.notchBounce == 0 ? L("Aus") : settings.notchBounce.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle(L("Töne"), isOn: setting(\.soundsEnabled))
            }
            Section(L("Bedienung")) {
                Picker(L("Beim Aufklappen zeigen"), selection: setting(\.panelOpenBehavior)) {
                    Text(L("Wo gerade etwas passiert")).tag(PanelOpenBehavior.activity)
                    Text(L("Zuletzt gewählten Reiter")).tag(PanelOpenBehavior.lastUsed)
                }
                if settings.panelOpenBehavior == .activity {
                    Text(L("Wartet Claude Code oder Codex auf dich, öffnen sich die Sessions. Sonst öffnet laufende Musik den Reiter „Musik“, arbeitende Agenten die Sessions."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent(L("Hover-Verzögerung")) {
                    HStack {
                        Slider(value: integerSetting(\.hoverDelayMs), in: 0...1000, step: 25)
                        Text(L("{0} ms", settings.hoverDelayMs))
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                LabeledContent(L("Island-Breite je Seite")) {
                    HStack {
                        Slider(value: setting(\.islandSideWidth), in: AppSettings.islandSideWidthRange, step: 5)
                        Text(L("{0} pt", Int(settings.islandSideWidth)))
                            .monospacedDigit()
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Agenten

    /// Hooks von Claude Code und Codex: Status, neu einrichten, alles entfernen.
    private var agentsPane: some View {
        SettingsPage(pane: .agents) {
            Section(L("Verbindung")) {
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
                    Button(L("Einrichtung …"), action: openAssistant)
                    Button(L("Neu einrichten")) {
                        setup.connectClaude()
                        setup.connectCodex()
                    }
                    Spacer()
                    Button(L("Sicherungen zeigen")) { setup.showBackups() }
                    Button(L("Alles entfernen")) { setup.removeAll() }
                }
            }
        }
        .onAppear { setup.refresh() }
    }

    private func connection(_ installed: Bool?) -> StatusBadge {
        switch installed {
        case .some(true): StatusBadge(text: L("Verbunden"), color: Color.green)
        case .some(false): StatusBadge(text: L("Nicht verbunden"), color: Color.orange)
        case .none: StatusBadge(text: L("Unbekannt"), color: Color.gray)
        }
    }

    // MARK: - Sessions

    private var sessionsPane: some View {
        SettingsPage(pane: .sessions) {
            Section(L("Ansicht")) {
                SessionStylePicker(selection: setting(\.sessionViewStyle),
                                   claude: Color(hex: settingsStore.settings.claudeColorHex),
                                   codex: Color(hex: settingsStore.settings.codexColorHex))
                Text(SessionStylePicker.explanation(settingsStore.settings.sessionViewStyle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(L("Titel"), selection: setting(\.sessionTitleSource)) {
                    Text(L("Letzte Aufgabe")).tag(SessionTitleSource.lastPrompt)
                    Text(L("Session-Titel bevorzugen")).tag(SessionTitleSource.sessionTitle)
                }
                Toggle(L("Claude Code beobachten"), isOn: setting(\.watchClaude))
                Toggle(L("Codex beobachten"), isOn: setting(\.watchCodex))
            }
            Section(L("Signale")) {
                Toggle(L("Bei Fragen"), isOn: setting(\.signalOnQuestion))
                Toggle(L("Bei Freigaben"), isOn: setting(\.signalOnPermission))
                Toggle(L("Bei Abschluss"), isOn: setting(\.signalOnDone))
                Toggle(L("Bei Fehlern"), isOn: setting(\.signalOnError))
                LabeledContent(L("Freigabe-Wartezeit")) {
                    HStack {
                        Slider(value: integerSetting(\.approvalTimeoutSeconds), in: 5...125, step: 5)
                        Text("\(settingsStore.settings.approvalTimeoutSeconds) s")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            Section(L("Antworten")) {
                Toggle(L("Antworten an Claude automatisch eintippen"), isOn: setting(\.autoSendClaudeReplies))
            }
        }
    }

    // MARK: - Musik

    private var musicPane: some View {
        let settings = settingsStore.settings
        return SettingsPage(pane: .music) {
            Section {
                MusicPreviewCard(settings: settings)
                Toggle(L("Musikanzeige"), isOn: setting(\.musicEnabled))
            }
            Section(L("Was zeigt die Notch?")) {
                ChoiceCards(options: [(MusicSourceMode.musicServices, L("Nur Musikdienste")),
                                      (.allPlayers, L("Alles, was abspielt"))],
                            selection: setting(\.musicSourceMode)) { mode in
                    sourceThumbnail(mode)
                }
                Text(sourceModeHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.musicSourceMode == .musicServices {
                    Toggle(L("Musik im Browser erkennen (YouTube Music, Spotify Web …)"), isOn: setting(\.musicBrowserMusic))
                    Toggle(L("Podcasts zeigen"), isOn: setting(\.musicIncludePodcasts))
                }
            }
            Section(L("Neuer Titel")) {
                ChoiceCards(options: [(TrackChangeStyle.island, L("Seitlich")), (.banner, L("Ausgefahren")),
                                      (.off, L("Aus"))],
                            selection: setting(\.musicTrackChangeStyle)) { style in
                    TrackChangeThumbnail(style: style)
                }
                Text(trackChangeHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.musicTrackChangeStyle != .off {
                    Picker(L("Anzeigedauer"), selection: setting(\.musicTrackChangeSeconds)) {
                        ForEach(AppSettings.trackChangeSecondChoices, id: \.self) { seconds in
                            Text(L("{0} s", Int(seconds))).tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Spacer()
                        TryOutButton(action: music.previewTrackChange)
                    }
                }
            }
            Section(L("Balken")) {
                Picker(L("Balken neben der Kamera"), selection: setting(\.musicVisualizer)) {
                    Text(L("Echt, zur Musik")).tag(MusicVisualizerMode.audio)
                    Text(L("Animiert")).tag(MusicVisualizerMode.animated)
                }
                .pickerStyle(.segmented)
                Text(settings.musicVisualizer == .audio
                     ? L("Für echte Balken hört notchai den Ton mit, der gerade spielt, und rechnet daraus die Höhen. Das bleibt auf diesem Mac, nichts wird gespeichert. Beim ersten Mal fragt macOS, ob notchai Systemaudio aufnehmen darf.")
                     : L("Die Balken tanzen gleichmäßig, ohne den Ton abzugreifen."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.musicVisualizer == .audio, let visualizer = music.visualizer {
                    VisualizerStatusRow(status: visualizer.status)
                }
            }
            Section(L("Darstellung")) {
                Toggle(L("Eingeklappt neben der Kamera (Cover und Balken)"), isOn: setting(\.musicCompactView))
                Toggle(L("Hintergrund in den Farben des Covers"), isOn: setting(\.musicArtworkBackground))
                Picker(L("Cover beim Titelwechsel"), selection: setting(\.musicCoverTransition)) {
                    Text(L("Weich überblenden")).tag(CoverTransitionStyle.blur)
                    Text(L("In Skip-Richtung umklappen")).tag(CoverTransitionStyle.flip)
                }
                Toggle(L("Leuchten in der Farbe des Covers"), isOn: setting(\.musicCoverGlow))
                Toggle(L("Cover laden"), isOn: setting(\.musicLoadArtwork))
                Text(L("Cover kommen per AppleScript aus Spotify und Musik; beim ersten Mal fragt macOS, ob notchai die App steuern darf. Spotify-Cover lädt notchai von Spotifys Bildserver."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            knownPlayersSection
        }
    }

    private var trackChangeHint: String {
        switch settingsStore.settings.musicTrackChangeStyle {
        case .island: L("Beim nächsten Titel fährt die Notch kurz zur Seite aus: links Cover, Titel und Interpret, rechts ein Visualizer zur Musik.")
        case .banner: L("Beim nächsten Titel fährt die Notch kurz nach unten aus, mit großem Cover, Titel und Interpret.")
        case .off: L("Beim nächsten Titel wechselt nur das Cover neben der Kamera.")
        }
    }

    private var sourceModeHint: String {
        switch settingsStore.settings.musicSourceMode {
        case .musicServices:
            L("Spotify, Apple Music, TIDAL und Co. Ein YouTube-Video im Browser erscheint nicht; Musik im Browser erkennt notchai daran, dass die Seite ein Album meldet.")
        case .allPlayers:
            L("Alles, was macOS als „Jetzt läuft“ meldet, auch Videos im Browser.")
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
        return Section(L("Erkannte Player")) {
            if players.isEmpty {
                Text(L("Noch keine. Sobald etwas abspielt, erscheint die App hier."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(players, id: \.key) { player in
                    let kind = PlayerCatalog.kind(of: PlayerSource(bundleId: player.key.hasPrefix("name:") ? nil : player.key,
                                                                   name: player.name))
                    Picker(selection: ruleSetting(player.key)) {
                        Text(L("Automatisch")).tag(MusicSourceRule.automatic)
                        Text(L("Immer zeigen")).tag(MusicSourceRule.always)
                        Text(L("Nie zeigen")).tag(MusicSourceRule.never)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                            Text(L("{0} · automatisch: {1}", kind.label, MusicFilter.automaticSummary(for: kind, settings: settings)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(L("Liste leeren")) {
                        settingsStore.settings.musicKnownSources = [:]
                        settingsStore.settings.musicSourceRules = [:]
                    }
                    .help(L("Entfernt alle erkannten Player samt ihrer Regeln."))
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
            Section(L("Pixel-Büro")) {
                Toggle(L("Büro aktivieren"), isOn: setting(\.officeEnabled))
                LabeledContent(L("Größe")) {
                    HStack {
                        Slider(value: setting(\.officeScale), in: 0.5...2, step: 0.1)
                        Text(settingsStore.settings.officeScale, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker(L("Beleuchtung"), selection: setting(\.officeLighting)) {
                    Text(L("Echte Sonne")).tag(OfficeLighting.realSun)
                    Text(L("Fester Tag")).tag(OfficeLighting.fixedDay)
                    Text(L("Feste Nacht")).tag(OfficeLighting.fixedNight)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Büro-Ton"), isOn: setting(\.officeSound))
                        .disabled(true)
                    Text(L("Lo-Fi-Musik für die Halle kommt später."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Tastenkürzel")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Zweimal rechte ⌘ öffnet das Büro"), isOn: setting(\.officeHotkey))
                    Text(L("Geht auch, wenn eine andere App vorn ist. Ohne Kürzel öffnet ein Klick im Reiter „Büro“ oder „Büro öffnen“ im Menü die Halle groß."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if settingsStore.settings.officeHotkey && !DoubleTapHotkeys.isTrusted {
                    LabeledContent(L("Bedienungshilfen")) {
                        Button(L("Erlauben …")) { DoubleTapHotkeys.openAccessibilitySettings() }
                    }
                    Text(L("Damit notchai die ⌘-Taste in anderen Apps bemerkt, braucht es die Berechtigung „Bedienungshilfen“ (Datenschutz & Sicherheit)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Standort für den Sonnenstand (optional)")) {
                CoordinateField(kind: .latitude, settingsStore: settingsStore)
                CoordinateField(kind: .longitude, settingsStore: settingsStore)
            }
        }
    }

    // MARK: - Ablage

    private var shelfPane: some View {
        let count = shelfStore.shelf.items.count
        return SettingsPage(pane: .shelf) {
            Section(L("Dateien in die Notch ziehen")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Ablage aktivieren"), isOn: setting(\.shelfEnabled))
                    Text(L("Ziehst du Dateien aus dem Finder, Mail oder einer anderen App zur Notch, klappt sie auf und zeigt zwei Ziele: AirDrop sendet an ein Gerät in der Nähe, die Ablage hebt sie kurz auf."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L("Abgelegte Dateien")) {
                LabeledContent(L("In der Ablage")) {
                    Text(count == 1 ? L("1 Datei") : L("{0} Dateien", count))
                        .monospacedDigit()
                }
                LabeledContent(L("Ablage leeren")) {
                    Button(L("Leeren")) { shelfStore.removeAll() }
                        .disabled(count == 0)
                }
                Text(L("notchai merkt sich nur, wo die Dateien liegen; kopiert oder verschoben wird nichts. Wer eine Datei aus der Notch zieht, bekommt eine Kopie. Gelöschte Dateien verschwinden von selbst aus der Ablage."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Notizen

    private var notesPane: some View {
        let count = noteStore.book.notes.count
        return SettingsPage(pane: .notes) {
            Section(L("Schnellnotiz")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Zweimal ⌃ öffnet eine Schnellnotiz"), isOn: setting(\.notesHotkey))
                    Text(L("Die Notch klappt auf, du schreibst, ↩ speichert und sie klappt wieder zu. Escape schließt, ohne zu speichern; der Entwurf bleibt. Ohne Kürzel schreibst du im Reiter „Notizen“."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if settingsStore.settings.notesHotkey && !DoubleTapHotkeys.isTrusted {
                    LabeledContent(L("Bedienungshilfen")) {
                        Button(L("Erlauben …")) { DoubleTapHotkeys.openAccessibilitySettings() }
                    }
                    Text(L("Damit notchai die ⌃-Taste in anderen Apps bemerkt, braucht es die Berechtigung „Bedienungshilfen“ (Datenschutz & Sicherheit)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(L("Hast du „Diktieren“ in den Systemeinstellungen auf zweimal ⌃ gelegt, schalte eins von beiden um."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Gespeicherte Notizen")) {
                LabeledContent(L("Notizen")) {
                    Text(count == 1 ? L("1 Notiz") : L("{0} Notizen", count))
                        .monospacedDigit()
                }
                LabeledContent(L("Alle Notizen löschen")) {
                    Button(L("Löschen")) { noteStore.removeAll() }
                        .disabled(count == 0)
                }
                Text(L("Notizen bleiben auf diesem Mac. Ein Klick auf eine Notiz in der Notch kopiert sie, ✕ löscht sie."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Entwickler

    private var developerPane: some View {
        SettingsPage(pane: .developer) {
            Section(L("Test-Signale")) {
                LabeledContent(L("Freigabe von Claude Code")) { Button(L("Zeigen")) { developer.raiseSignal(SignalDemo.permission) } }
                LabeledContent(L("Frage von Codex")) { Button(L("Zeigen")) { developer.raiseSignal(SignalDemo.question) } }
                LabeledContent(L("Fertig")) { Button(L("Zeigen")) { developer.raiseSignal(SignalDemo.done) } }
                LabeledContent(L("Fehler")) { Button(L("Zeigen")) { developer.raiseSignal(SignalDemo.error) } }
                Picker(L("Signalform"), selection: Binding(
                    get: { settingsStore.settings.signalStyle },
                    set: { settingsStore.settings.signalStyle = $0; developer.restyleSignal() }
                )) {
                    Text(L("Island")).tag(SignalStyle.island)
                    Text(L("Banner")).tag(SignalStyle.banner)
                    Text(L("Vertikal")).tag(SignalStyle.vertical)
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    Button(L("Signal schließen"), action: developer.closeSignal)
                }
            }
            Section(L("Diagnose")) {
                LabeledContent(L("Letzte Hook-Ereignisse")) {
                    Button(L("Kopieren")) {
                        DeveloperTools.copy(developer.hookEventsText(), empty: L("Noch keine Hook-Ereignisse empfangen."))
                    }
                }
                LabeledContent(L("Jetzt-läuft-Rohdaten")) {
                    Button(L("Kopieren")) { DeveloperTools.copy(developer.nowPlayingText(), empty: L("Keine Rohdaten.")) }
                }
                LabeledContent(L("Protokolle")) { Button(L("Im Finder zeigen")) { DeveloperTools.reveal(DeveloperTools.logsFolder) } }
                LabeledContent(L("Daten von notchai")) { Button(L("Im Finder zeigen")) { DeveloperTools.reveal(DeveloperTools.dataFolder) } }
            }
            Section(L("Reaktion")) {
                let log = developer.responsiveness.log
                LabeledContent(L("Hänger")) {
                    Text(log.summary)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L("Liste der Hänger")) {
                    Button(L("Kopieren")) { DeveloperTools.copy(log.report(), empty: log.summary) }
                        .disabled(log.count == 0)
                }
                Text(L("Misst, solange die Entwickleroptionen an sind, wie schnell notchai reagiert, auch wie lange das Menü in der Menüleiste nach dem Klick braucht. Jeder Hänger ab 100 ms steht mit Uhrzeit und Zustand der Notch in der Liste."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Einrichtung")) {
                LabeledContent(L("Begrüßung und Einrichtung")) { Button(L("Erneut zeigen"), action: developer.showWelcome) }
                Text(L("Zeigt das Leuchten und den Einrichtungs-Assistenten wie beim ersten Start, ohne etwas zu löschen."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section(L("Zurücksetzen")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Setzt notchai auf „gerade installiert“ zurück: Hooks aus Claude Code und Codex entfernen, Einstellungen, Sicherungen, Protokolle und Caches in den Papierkorb legen, Berechtigungen zurücksetzen und neu starten."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(L("notchai zurücksetzen …"), role: .destructive, action: developer.resetApp)
                    }
                }
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
        case .latitude: L("Breitengrad")
        case .longitude: L("Längengrad")
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
