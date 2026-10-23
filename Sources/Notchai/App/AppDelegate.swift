import AppKit
import NotchaiCore
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController?
    private(set) var model: AppModel?
    private(set) var notchController: NotchController?
    private(set) var coordinator: HookCoordinator?
    private(set) var updates: UpdateController?
    private(set) var music: MusicMonitor?
    private(set) var office: OfficeWindowController?
    private var officeHotkey: OfficeHotkey?
    private var setupWindow: SetupWindowController?
    private var updateItem: NSMenuItem?
    /// Wartet irgendeine Session auf den Besitzer (laut Session-Buch)?
    private var sessionsWaiting = false
    private var dotVisible: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statusItemController = StatusItemController()
        self.statusItemController = statusItemController
        let model = AppModel(settingsStore: SettingsStore(fileURL: SettingsStore.defaultFileURL()))
        self.model = model
        let setup = SetupController(home: home)
        let updates = UpdateController(settingsStore: model.settingsStore)
        self.updates = updates
        let setupWindow = SetupWindowController(setup: setup, settingsStore: model.settingsStore)
        self.setupWindow = setupWindow
        let settingsWindowController = SettingsWindowController.shared
        settingsWindowController.configure(settingsStore: model.settingsStore, setup: setup, updates: updates,
                                           openAssistant: { [weak setupWindow] in setupWindow?.show() })
        statusItemController.setSettingsAction { settingsWindowController.show() }
        model.onOpenSettings = { [weak settingsWindowController] in settingsWindowController?.show() }
        let notchController = NotchController(model: model)
        self.notchController = notchController

        let coordinator = HookCoordinator(model: model, home: home)
        self.coordinator = coordinator
        model.onSignalChange = { [weak self, weak notchController] _ in
            self?.updateWaitingDot()
            notchController?.signalChanged()
        }
        // Entscheidungen aus Signal und Session-Zeile gehen an den wartenden Hook; Test-Signale schließen sich nur.
        model.onSignalAction = { [weak coordinator] id, action in coordinator?.decide(id, action: action) }
        model.onDecide = { [weak coordinator] id, action in coordinator?.decide(id, action: action) }
        model.onReply = { [weak coordinator] session, text in coordinator?.reply(text, to: session) }
        model.onFocusSession = { [weak coordinator] session in coordinator?.replies.focus(session) }
        coordinator.onWaitingChange = { [weak self] waiting in
            self?.sessionsWaiting = waiting
            self?.updateWaitingDot()
        }
        coordinator.start()

        let music = MusicMonitor(model: model)
        self.music = music
        music.start()

        // Lagerhalle: ein Klick auf eine Figur holt das Fenster ihrer Session nach vorn und schließt das Büro.
        let officeDirector = OfficeDirector(model: model)
        model.officeDirector = officeDirector
        let office = OfficeWindowController(settingsStore: model.settingsStore, director: officeDirector)
        self.office = office
        officeDirector.onFocus = { [weak model, weak office] session in
            office?.close()
            model?.onFocusSession?(session)
        }
        model.onOpenOffice = { [weak office] in office?.open() }
        let officeHotkey = OfficeHotkey(settingsStore: model.settingsStore)
        officeHotkey.onTrigger = { [weak office] in office?.toggle() }
        officeHotkey.start()
        self.officeHotkey = officeHotkey

        updateItem = statusItemController.addMenuItem("Nach Updates suchen …", section: .main) { [weak self] in
            self?.updateMenuAction()
        }
        statusItemController.addMenuItem("Büro öffnen", section: .main) { [weak office] in office?.open() }
        statusItemController.addMenuItem("Einrichtung …", section: .main) { [weak setupWindow] in setupWindow?.show() }
        observeUpdateState()
        updates.start()

        addDeveloperMenu(statusItemController, model: model)

        // Beim ersten Start richtet der Assistent die Hooks ein (jeder Schritt lässt sich überspringen).
        if !model.settingsStore.settings.setupCompleted { setupWindow.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Wartende Hooks bekommen sofort „keine Entscheidung“; die Agenten fragen dann selbst.
        coordinator?.stop()
    }

    /// Der Punkt zeigt nur, dass etwas auf den Besitzer wartet: eine Session laut Session-Buch
    /// oder das angezeigte Signal.
    private func updateWaitingDot() {
        let visible = sessionsWaiting || model?.activeSignal?.kind.isAwaitingOwner == true
        guard visible != dotVisible else { return }
        dotVisible = visible
        statusItemController?.setWaitingDot(visible)
    }

    // MARK: - Updates

    private func updateMenuAction() {
        guard let updates else { return }
        if updates.canInstall {
            Task { await updates.install() }
        } else {
            SettingsWindowController.shared.show()
            Task { await updates.check() }
        }
    }

    /// Hält den Menüeintrag auf dem Stand der Update-Prüfung.
    private func observeUpdateState() {
        guard let updates else { return }
        withObservationTracking {
            updateItem?.title = Self.menuTitle(for: updates.state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeUpdateState() }
        }
    }

    private static func menuTitle(for state: UpdateState) -> String {
        switch state {
        case .available(let offer): "Update installieren (\(offer.count) neu) …"
        case .releaseAvailable(let offer): "Update auf \(offer.version) installieren …"
        case .checking: "Suche nach Updates …"
        case .installing: "Update wird installiert …"
        default: "Nach Updates suchen …"
        }
    }

    // MARK: - Entwickler

    private func addDeveloperMenu(_ menu: StatusItemController, model: AppModel) {
        menu.addMenuItem("Test-Signal: Freigabe (Claude)", section: .developer) { [weak model] in
            model?.raiseSignal(SignalDemo.permission)
        }
        menu.addMenuItem("Test-Signal: Frage (Codex)", section: .developer) { [weak model] in
            model?.raiseSignal(SignalDemo.question)
        }
        menu.addMenuItem("Test-Signal: Fertig", section: .developer) { [weak model] in
            model?.raiseSignal(SignalDemo.done)
        }
        menu.addMenuItem("Test-Signal: Fehler", section: .developer) { [weak model] in
            model?.raiseSignal(SignalDemo.error)
        }
        menu.addMenuItem(.separator(), section: .developer)
        menu.addMenuItem("Signal schließen", section: .developer) { [weak model] in
            model?.clearActiveSignal()
        }
        menu.addMenuItem(.separator(), section: .developer)
        let styles: [(SignalStyle, String)] = [(.island, "Island"), (.banner, "Banner"), (.vertical, "Vertikal")]
        for (style, name) in styles {
            menu.addMenuItem("Signal-Form: \(name)", section: .developer) { [weak model] in
                guard let model else { return }
                model.settingsStore.settings.signalStyle = style
                // Ein offenes Signal sofort in der neuen Form zeigen.
                if let signal = model.activeSignal {
                    model.clearSignal(signal.id)
                    model.raiseSignal(signal)
                }
            }
        }
        menu.addMenuItem(.separator(), section: .developer)
        // Hilft bei den offenen Prüfungen aus `docs/hooks.md` (Umgebung der Claude-App, cmux …).
        menu.addMenuItem("Letzte Hook-Ereignisse kopieren", section: .developer) { [weak self] in
            guard let text = self?.coordinator?.recentEventsText() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text.isEmpty ? "Noch keine Hook-Ereignisse empfangen." : text, forType: .string)
        }
        // Hilft bei den offenen Prüfungen aus `docs/now-playing.md` (JXA-Felder, Schlüssel der Benachrichtigungen).
        menu.addMenuItem("Jetzt-läuft-Rohdaten kopieren", section: .developer) { [weak self] in
            guard let text = self?.music?.rawDataText() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
