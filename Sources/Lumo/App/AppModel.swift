import AppKit
import CoreGraphics
import Foundation
import LumoCore
import Observation

/// Zentraler Zustand der App. Spätere Stufen speisen hier über `send(_:)` Ereignisse ein.
@MainActor @Observable
final class AppModel {
    var notch = NotchState()
    let settingsStore: SettingsStore
    /// Reiter „Ablage“: abgelegte Dateien.
    let shelfStore: ShelfStore
    /// Reiter „Notizen“: Schnellnotizen.
    let noteStore: NoteStore
    /// Angefangene Notiz; übersteht Zu- und Aufklappen.
    var noteDraft = ""
    /// Bildschirm mit Notch; `nil`, wenn keiner angeschlossen oder aufgeklappt ist.
    var screen: ScreenInfo?
    /// Mehrere Notch-Bildschirme: Den Ruhezustand zeichnen die ruhenden Kopien (`ExternalNotchMirror`), die echte
    /// Notch erst, wenn sie aufklappt oder ein Signal zeigt. So ändert ein Wechsel des Bildschirms am Bild nichts.
    var mirrorsDrawIdle = false
    /// Die Notch ist zu und fertig zugeklappt; erst dann übernimmt die ruhende Kopie, sonst verschwände die Form
    /// mitten im Zuklappen.
    private(set) var idleSettled = true
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// Von SwiftUI gemessene Höhe des Panel-Inhalts je Reiter. So klappt das Panel gleich auf die richtige Höhe
    /// auf, statt erst die Höhe des vorigen Reiters anzusteuern und dann nachzufedern.
    private(set) var panelContentHeights: [PanelTab: CGFloat] = [:]
    /// Angezeigtes Signal samt Frist und Antwort-Entwurf; die Regeln dafür liegen getestet in `SignalLifecycle`.
    private(set) var signals = SignalLifecycle()
    /// Inhalt des gerade angezeigten Signals.
    var activeSignal: SignalContent? { signals.active?.content }
    /// Knopfbereich der Island („Erlauben?“, ✕/✓) in Panel-Koordinaten (Ursprung oben links);
    /// über ihm klappt Hover die Island nicht auf. `nil`, solange keine Island zu sehen ist.
    var islandButtonArea: CGRect?
    /// Empfängt die Entscheidung samt ID des Signals, auf dem sie getroffen wurde (bei Anfragen deren ID).
    /// Kommt nur an, solange genau dieses Signal angezeigt wird. Bei Test-Signalen schließt jede Aktion das Signal.
    @ObservationIgnored var onSignalAction: ((UUID, SignalAction) -> Void)?
    /// Meldet jedes neue oder geschlossene Signal (Menüleisten-Punkt, Tastaturfokus).
    @ObservationIgnored var onSignalChange: ((SignalContent?) -> Void)?
    /// Öffnet das Einstellungsfenster aus Menü oder Panel.
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored private var autoDismissTask: Task<Void, Never>?

    /// Sichtbare Sessions, sortiert und gefiltert vom `SessionBook`.
    var sessions: [AgentSession] = []
    /// Fußzeile der Session-Liste.
    var dailyStats = DailyStats(tasks: 0, minutes: 0, files: 0)
    /// Kurzer Hinweis nach einer Antwort („Gesendet“ …); verschwindet nach wenigen Sekunden.
    private(set) var notice: String?
    /// Session, deren Antwortfeld in der Liste bzw. Detailkarte offen ist.
    var replyTargetID: String?
    /// Session, deren Details der Reiter „Sessions“ statt der Liste zeigt (Klick auf eine Zeile).
    var detailSessionID: String?
    /// Die Session zu `detailSessionID`, solange sie noch zu sehen ist; sonst zeigt der Reiter wieder die Liste.
    var detailSession: AgentSession? {
        detailSessionID.flatMap { id in sessions.first { $0.id == id } }
    }
    /// Entwürfe der Antwortfelder je Session; überstehen Zu- und Aufklappen.
    private(set) var replyDrafts: [String: String] = [:]
    /// Entscheidung zu einer wartenden Anfrage aus einer Session-Zeile (ID = Request-ID).
    @ObservationIgnored var onDecide: ((UUID, SignalAction) -> Void)?
    /// Antwort an eine Session aus Liste oder Detailkarte.
    @ObservationIgnored var onReply: ((AgentSession, String) -> Void)?
    /// Klick auf eine Session: ihr Fenster nach vorn holen.
    @ObservationIgnored var onFocusSession: ((AgentSession) -> Void)?
    /// Session aus der Notch nehmen, bis sie wieder etwas tut.
    @ObservationIgnored var onDismissSession: ((AgentSession) -> Void)?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    /// Was gerade läuft, schon gefiltert (`MusicMonitor`).
    var nowPlaying: NowPlaying?
    /// Cover des Titels; ohne Cover das Symbol der App.
    var artwork: NSImage?
    var musicAppIcon: NSImage?
    /// Leuchtfarbe aus dem Cover; `nil` bei farblosen oder fehlenden Covern.
    var artworkGlow: RGB?
    /// Eingeklappte Musikanzeige (läuft gerade oder wurde eben erst pausiert).
    var showsCompactMusic = false
    /// Titel (`NowPlaying.trackKey`), zu dem das angezeigte Cover gehört; sein Wechsel lässt das Cover umklappen.
    var artworkTrack: String?
    /// Richtung, in die das Cover beim nächsten Wechsel umklappt.
    var skipDirection: SkipDirection = .forward
    /// Play/Pause sofort umschalten, bis der Player den neuen Zustand meldet.
    var musicPlayingOverride: Bool?
    /// Letzter Befehl samt Zeitpunkt (für die Richtung des Umklappens).
    @ObservationIgnored private(set) var lastMusicCommand: (command: MusicCommand, at: Date)?
    /// Zurück, Play/Pause, Weiter aus dem Reiter „Musik“.
    @ObservationIgnored var onMusicCommand: ((MusicCommand) -> Void)?
    /// Spulen an eine Stelle (Sekunden).
    @ObservationIgnored var onMusicSeek: ((TimeInterval) -> Void)?
    /// Neue Stelle nach dem Spulen, bis der Player sie meldet.
    var musicSeek: MusicScrub.Override?
    /// Gerade wird im Fortschrittsbalken gezogen: Die Notch bleibt offen, auch wenn der Zeiger sie verlässt.
    var isScrubbing = false
    /// Höhen der Balken aus dem echten Ton (`MusicVisualizer`): Anzahl und Zeitpunkt des Bildes rein, Höhen raus;
    /// `nil` heißt „kein echter Ton“, dann tanzen die Balken von selbst.
    @ObservationIgnored var musicLevels: ((Int, TimeInterval) -> [Double]?)?
    /// Wie `musicLevels`, für den Visualizer mit vielen Balken: gemeinsam eingepegelt, mit Spitzen.
    @ObservationIgnored var musicSpectrum: ((Int, TimeInterval) -> MusicVisualizer.Spectrum?)?
    /// Neuer Titel, den die Notch gerade kurz ausgefahren zeigt (`TrackChangeStyle`).
    private(set) var trackAnnouncement: TrackAnnouncement?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    /// Zuletzt gezeigte Form und Richtung des Wechsels dorthin (nur für die Wahl der Animation).
    @ObservationIgnored private var shownPresentation: NotchPresentation = .idle
    @ObservationIgnored private var shownMotion: NotchMotion = .expand
    @ObservationIgnored private var overrideTask: Task<Void, Never>?

    /// Die Notch leuchtet in wechselnden Farben, solange die Einrichtung offen ist.
    var setupGlow = false

    /// Lagerhalle: Bild und Figuren für Reiter und großes Fenster.
    @ObservationIgnored var officeDirector: OfficeDirector?
    /// Öffnet das große Büro.
    @ObservationIgnored var onOpenOffice: (() -> Void)?

    init(settingsStore: SettingsStore, shelfStore: ShelfStore, noteStore: NoteStore) {
        self.settingsStore = settingsStore
        self.shelfStore = shelfStore
        self.noteStore = noteStore
    }

    func send(_ e: NotchEvent) {
        let settings = settingsStore.settings
        // Was der Besitzer selbst öffnet und jedes Signal gehen vor; der neue Titel weicht sofort.
        switch e {
        case .hoverBegan, .signalRaised, .fileDragEntered, .noteShortcut: endTrackAnnouncement()
        default: break
        }
        if e == .hoverBegan, notch.mode == .idle {
            // Aufklappen dort, wo gerade etwas passiert (oder im zuletzt gewählten Reiter).
            notch.openTab = PanelTabChoice.tab(behavior: settings.panelOpenBehavior, lastTab: notch.lastTab,
                                               activity: currentActivity)
        }
        let wasIdle = notch.mode == .idle
        notch.apply(e, style: settings.signalStyle)
        if notch.mode != .idle {
            settleTask?.cancel()
            if idleSettled { idleSettled = false }
        } else if !wasIdle {
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, let self, notch.mode == .idle else { return }
                idleSettled = true
            }
        }
    }

    /// Was gerade los ist: Anfrage eines Agenten, laufende Musik, arbeitende Sessions.
    var currentActivity: NotchActivity {
        NotchActivity(
            ownerAwaited: sessions.contains { $0.status.isWaiting } || activeSignal?.kind.isAwaitingOwner == true,
            musicPlaying: nowPlaying?.isPlaying == true,
            sessionsRunning: sessions.contains { $0.status == .working }
        )
    }

    func setPanelContentHeight(_ height: CGFloat, for tab: PanelTab) {
        guard abs((panelContentHeights[tab] ?? 0) - height) > 0.5 else { return }
        panelContentHeights[tab] = height
    }

    /// Schätzung, bis ein Reiter einmal gemessen ist.
    private static func estimatedPanelHeight(_ tab: PanelTab) -> CGFloat {
        switch tab {
        case .music: 147
        case .sessions: 170
        case .office: OfficeTabView.previewSize.height + 52
        case .shelf: 176
        case .notes: 190
        }
    }

    /// Zeigt ein Signal; ein anderes, schon angezeigtes wird ersetzt. Dieselbe ID behält ihren Entwurf.
    func raiseSignal(_ c: SignalContent) {
        signals.raise(c, now: .now)
        send(.signalRaised)
        scheduleAutoDismiss()
        onSignalChange?(c)
    }

    /// Schließt das Signal `id`; ist inzwischen ein anderes zu sehen, bleibt es stehen.
    func clearSignal(_ id: UUID) {
        guard signals.clear(id) != nil else { return }
        signalDidClose()
    }

    /// Schließt, was gerade angezeigt wird (Entwickler-Seite der Einstellungen).
    func clearActiveSignal() {
        guard signals.clearActive() != nil else { return }
        signalDidClose()
    }

    /// Wird von den Knöpfen und dem Antwortfeld im Signal `id` aufgerufen. Ein Klick auf ein inzwischen
    /// ersetztes Signal oder eine unpassende Aktion wird verworfen.
    func performSignalAction(_ action: SignalAction, for id: UUID) {
        guard signals.accepts(action, for: id) else { return }
        if let onSignalAction {
            onSignalAction(id, action)
        } else {
            clearSignal(id)
        }
    }

    /// Gewählte Optionen einer Mehrfachauswahl im Signal `id`.
    func selection(for id: UUID) -> Set<String> { signals.selection(for: id) }
    func toggleOption(_ option: String, for id: UUID) { signals.toggle(option, for: id) }

    /// Mehrfachauswahl abschicken: gewählte Optionen und getippter Text zusammen.
    func submitSelection(for id: UUID) {
        guard let content = activeSignal, content.id == id,
              let answer = content.multiSelectAnswer(selected: selection(for: id), typed: draft(for: id)) else { return }
        performSignalAction(answer, for: id)
    }

    /// Hinweis „+1 Zeile“ im Signal: die Sessions zeigen die Anfrage mit dem ganzen Befehl.
    func showFullRequest() { send(.openPanel(.sessions)) }

    /// Antwort-Entwurf des Signals `id`; übersteht Zu- und Aufklappen.
    func draft(for id: UUID) -> String { signals.draft(for: id) }
    func setDraft(_ text: String, for id: UUID) {
        // Unveränderter Text löst kein neues Zeichnen aus.
        guard signals.draft(for: id) != text else { return }
        signals.setDraft(text, for: id)
    }

    private func signalDidClose() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        send(.signalCleared)
        onSignalChange?(nil)
    }

    /// „Fertig“ schließt sich zur Frist selbst; welches Signal das trifft, entscheidet `SignalLifecycle`.
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        guard let deadline = signals.active?.dismissAt else { return }
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self, signals.expire(now: .now) != nil else { return }
            signalDidClose()
        }
    }

    func openSettings() {
        onOpenSettings?()
    }

    /// Großes Büro aus dem Reiter öffnen; die Notch klappt dabei zu, damit sie nicht davor hängt.
    func openOffice() {
        send(.hoverEnded)
        onOpenOffice?()
    }

    /// Zeigt `text` für ein paar Sekunden in der Notch.
    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func replyDraft(for sessionID: String) -> String { replyDrafts[sessionID] ?? "" }
    func setReplyDraft(_ text: String, for sessionID: String) {
        guard replyDrafts[sessionID, default: ""] != text else { return }
        replyDrafts[sessionID] = text
    }

    /// Speichert die angefangene Notiz. Das Feld bleibt aktiv, die nächste Notiz lässt sich gleich tippen;
    /// Escape oder ein Klick woandershin schließt.
    func saveNote() {
        guard noteStore.add(noteDraft) != nil else { return }
        noteDraft = ""
    }

    func openSessionDetail(_ session: AgentSession) {
        detailSessionID = session.id
    }

    func closeSessionDetail() {
        detailSessionID = nil
    }

    /// Nimmt die Session aus der Notch, bis sie wieder etwas tut (`SessionBook.dismiss`).
    func dismissSession(_ session: AgentSession) {
        if detailSessionID == session.id { detailSessionID = nil }
        if replyTargetID == session.id { replyTargetID = nil }
        onDismissSession?(session)
        showNotice(L("Entfernt – kommt zurück, sobald die Session wieder etwas tut"))
    }

    /// Schickt den Entwurf an die Session und schließt das Antwortfeld.
    func sendReply(to session: AgentSession) {
        let text = replyDraft(for: session.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        replyDrafts[session.id] = nil
        replyTargetID = nil
        onReply?(session, text)
    }

    func sendMusicCommand(_ command: MusicCommand) {
        lastMusicCommand = (command, .now)
        switch command {
        case .next: skipDirection = .forward
        case .previous: skipDirection = .backward
        case .playPause:
            musicPlayingOverride = !displayedMusicPlaying
            overrideTask?.cancel()
            overrideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.musicPlayingOverride = nil
            }
        }
        onMusicCommand?(command)
    }

    /// Zeigt einen neuen Titel für die eingestellte Dauer, wenn die Notch gerade nichts anderes zeigt.
    func announceTrack(_ announcement: TrackAnnouncement) {
        guard announcement.style != .off, notch.mode == .idle else { return }
        trackAnnouncement = announcement
        announcementTask?.cancel()
        let seconds = settingsStore.settings.musicTrackChangeSeconds
        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.trackAnnouncement = nil
        }
    }

    /// Einstellungen › Musik: So sieht ein neuer Titel aus (mit dem, was gerade läuft, sonst mit einem Beispiel).
    func previewTrackAnnouncement() {
        let style = settingsStore.settings.musicTrackChangeStyle
        guard style != .off else { return }
        if let item = nowPlaying {
            announceTrack(TrackAnnouncement(style: style, title: item.title, artist: item.artist, artwork: artwork,
                                            appIcon: musicAppIcon, glow: artworkGlow))
        } else {
            announceTrack(TrackAnnouncement(style: style, title: L("Nächster Titel"), artist: "lumo",
                                            artwork: nil, appIcon: nil, glow: nil))
        }
    }

    private func endTrackAnnouncement() {
        announcementTask?.cancel()
        announcementTask = nil
        if trackAnnouncement != nil { trackAnnouncement = nil }
    }

    func seekMusic(to position: TimeInterval) {
        guard let item = nowPlaying else { return }
        musicSeek = MusicScrub.Override(position: position, track: item.trackKey, playing: displayedMusicPlaying, at: .now)
        onMusicSeek?(position)
    }

    /// Position im Balken: nach dem Spulen die neue Stelle, sonst die gemeldete.
    func displayedPosition(of item: NowPlaying, at date: Date) -> TimeInterval? {
        if let seek = musicSeek, seek.track == item.trackKey {
            return min(seek.position(at: date), item.duration ?? .infinity)
        }
        return item.position(at: date)
    }

    /// Größe der Hardware-Notch; kleiner wird die Form nie, auch nicht mitten in einer Animation.
    var notchSize: CGSize? { screen.flatMap(NotchGeometry.notchRect)?.size }

    /// Richtung des Wechsels zur Form `presentation`: Aufklappen federt, Zuklappen läuft ruhig aus.
    /// Merkt sich die zuletzt gezeigte Form; mehrfaches Zeichnen derselben Form ändert nichts.
    func motion(toward presentation: NotchPresentation) -> NotchMotion {
        guard presentation != shownPresentation else { return shownMotion }
        if let screen, let from = NotchGeometry.frame(for: shownPresentation, screen: screen, islandSideWidth: islandSideWidth),
           let to = NotchGeometry.frame(for: presentation, screen: screen, islandSideWidth: islandSideWidth) {
            shownMotion = NotchMotion.between(from.size, to.size)
        }
        shownPresentation = presentation
        return shownMotion
    }

    private var islandSideWidth: CGFloat { CGFloat(settingsStore.settings.islandSideWidth) }

    /// Spielt der Titel (mit sofortiger Rückmeldung nach einem Klick auf Play/Pause)?
    var displayedMusicPlaying: Bool { musicPlayingOverride ?? nowPlaying?.isPlaying ?? false }

    /// Der Reiter „Musik“ ist offen (dann wird öfter abgefragt).
    var musicTabOpen: Bool { notch.mode == .panel(.music) }

    /// Stehen gerade Balken in der Notch, die sich zur laufenden Musik bewegen?
    var showsMusicBars: Bool {
        guard displayedMusicPlaying else { return false }
        switch currentPresentation() {
        case .compact, .trackSides, .trackBanner, .externalIdle: return true
        default: return musicTabOpen
        }
    }


    /// Im aufgeklappten Panel ist ein Antwortfeld offen, oder der Reiter „Notizen“ mit seinem Notizfeld.
    var panelAcceptsText: Bool {
        guard case .panel(let tab) = notch.mode else { return false }
        return replyTargetID != nil || tab == .notes
    }

    /// Darf das Panel die Tastatur bekommen? Nur für ein sichtbares Antwortfeld.
    var acceptsKeyboard: Bool { signalAcceptsText || panelAcceptsText }

    /// Nur ein aufgeklapptes Signal mit Antwortfeld darf die Tastatur bekommen.
    var signalAcceptsText: Bool {
        guard activeSignal?.kind.acceptsText == true else { return false }
        return notch.mode == .signal(.banner) || notch.mode == .signal(.vertical)
    }

    func currentPresentation() -> NotchPresentation {
        switch notch.mode {
        // Laufende Musik zeigt sich eingeklappt; ein Signal verdrängt sie.
        // Ein neuer Titel fährt kurz über alles aus, was im Ruhezustand zu sehen ist.
        case .idle:
            if let presentation = trackAnnouncement?.style.presentation { presentation }
            // Externer Bildschirm: Die Mitte ist sichtbar und zeigt Uhrzeit, Status und Musik (`ExternalIdleView`).
            else if screen?.isVirtual == true { .externalIdle }
            else if showsCompactMusic { .compact }
            else { .idle }
        case .signal(.island): .island
        case .signal(.banner): .banner
        // „Fertig“ und „Fehler“ zeigen nur die Kopfzeile; der Kasten wird so hoch wie nötig.
        case .signal(.vertical): activeSignal?.kind.isAwaitingOwner == false ? .verticalCompact : .vertical
        // Nie kleiner als die Notch, auch bevor der Inhalt gemessen ist.
        case .panel(let tab):
            .panel(height: max(panelContentHeights[tab] ?? Self.estimatedPanelHeight(tab), screen?.topInset ?? 0))
        }
    }

    /// Kurz, was die Notch gerade zeigt und tut (für die Liste der Hänger auf der Seite „Entwickler“).
    func diagnosticContext() -> String {
        var parts: [String] = []
        switch notch.mode {
        case .idle:
            parts.append(trackAnnouncement != nil ? L("Notch: neuer Titel")
                : showsCompactMusic ? L("Notch: Musik eingeklappt") : L("Notch: zu"))
        case .signal(let style): parts.append("Notch: Signal (\(style.rawValue))")
        case .panel(let tab): parts.append("Notch: \(tab.title)")
        }
        if nowPlaying?.isPlaying == true { parts.append(L("Musik spielt")) }
        if !sessions.isEmpty { parts.append(sessions.count == 1 ? L("1 Session") : L("{0} Sessions", sessions.count)) }
        return parts.joined(separator: " · ")
    }

    /// Rahmen der gerade sichtbaren Form in Bildschirmkoordinaten; `nil` ohne Notch.
    func visibleFrame() -> CGRect? {
        guard let screen else { return nil }
        return NotchGeometry.frame(for: currentPresentation(), screen: screen,
                                   islandSideWidth: CGFloat(settingsStore.settings.islandSideWidth))
    }
}
