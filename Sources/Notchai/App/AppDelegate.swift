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
    private let responsiveness = ResponsivenessMonitor()
    /// Hält App Nap fern: Agenten warten auf die Antwort der Notch, und ein Klick in die Menüleiste soll sofort wirken.
    private var activity: NSObjectProtocol?
    /// Sprache, in der Menüs und Fenstertitel gerade stehen.
    private var appliedLanguage: AppLanguage?
    /// Wartet irgendeine Session auf den Besitzer (laut Session-Buch)?
    private var sessionsWaiting = false
    private var dotVisible: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "notchai beantwortet Fragen und Freigaben von Claude Code und Codex sofort")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsStore = SettingsStore(fileURL: SettingsStore.defaultFileURL())
        // Die Sprache steht fest, bevor irgendein Text entsteht (Menüs, Notch, Fenster).
        LanguageSwitch.apply(settingsStore.settings)
        appliedLanguage = Localization.language
        NSApp.mainMenu = MainMenu.make()
        let statusItemController = StatusItemController()
        self.statusItemController = statusItemController
        let model = AppModel(settingsStore: settingsStore, shelfStore: ShelfStore(fileURL: ShelfStore.defaultFileURL()))
        self.model = model
        let setup = SetupController(home: home)
        let updates = UpdateController(settingsStore: model.settingsStore)
        self.updates = updates
        let setupWindow = SetupWindowController(setup: setup, model: model)
        self.setupWindow = setupWindow
        let settingsWindowController = SettingsWindowController.shared
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

        settingsWindowController.configure(
            settingsStore: model.settingsStore, shelfStore: model.shelfStore, setup: setup, updates: updates,
            developer: makeDeveloperTools(model: model, setupWindow: setupWindow),
            openAssistant: { [weak setupWindow] in setupWindow?.show() },
            tryOut: { [weak model] in model?.raiseSignal(SignalDemo.preview) })

        updateItem = statusItemController.addMenuItem({ [weak updates] in Self.menuTitle(for: updates?.state ?? .idle) }) {
            [weak self] in self?.updateMenuAction()
        }
        statusItemController.addMenuItem({ L("Büro öffnen") }) { [weak office] in office?.open() }
        statusItemController.addMenuItem({ L("Einrichtung …") }) { [weak setupWindow] in setupWindow?.show() }
        observeUpdateState()
        updates.start()

        // Wie schnell notchai reagiert: Die Seite „Entwickler“ listet jeden spürbaren Hänger.
        responsiveness.context = { [weak model, weak office] in
            let parts = [model?.diagnosticContext() ?? "", office?.isOpen == true ? L("Büro offen") : "",
                         settingsWindowController.isVisible ? L("Einstellungen offen") : ""]
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        statusItemController.onMenuOpen = { [weak self] delay in self?.responsiveness.menuOpened(after: delay) }
        observeDeveloperOptions()
        observeLanguage()

        // Beim ersten Start leuchtet der Bildschirm auf, das Leuchten zieht sich in die Notch zusammen, und der
        // Assistent richtet alles ein (jeder Schritt lässt sich überspringen).
        if !model.settingsStore.settings.setupCompleted { setupWindow.showWithIntro() }
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
        case .checking: L("Suche nach Updates …")
        case .installing: L("Update wird installiert …")
        default: L("Nach Updates suchen …")
        }
    }

    // MARK: - Entwickler

    /// Nach einem Sprachwechsel bekommen Menüs und Fenstertitel die neuen Texte (die SwiftUI-Ansichten bauen sich
    /// selbst neu auf).
    private func observeLanguage() {
        guard let model else { return }
        withObservationTracking {
            _ = model.settingsStore.settings.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let model = self.model else { return }
                // Beobachtet werden alle Einstellungen; neu beschriftet wird nur bei einer anderen Sprache.
                LanguageSwitch.apply(model.settingsStore.settings)
                if Localization.language != appliedLanguage {
                    appliedLanguage = Localization.language
                    NSApp.mainMenu = MainMenu.make()
                    statusItemController?.relocalize()
                    SettingsWindowController.shared.relocalize()
                    setupWindow?.relocalize()
                }
                observeLanguage()
            }
        }
    }

    /// Die Messung der Reaktionszeit läuft nur, solange die Entwickleroptionen an sind.
    private func observeDeveloperOptions() {
        guard let model else { return }
        withObservationTracking {
            if model.settingsStore.settings.developerOptions {
                responsiveness.start()
            } else {
                responsiveness.stop()
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeDeveloperOptions() }
        }
    }

    /// Werkzeuge der Seite „Entwickler“ in den Einstellungen.
    private func makeDeveloperTools(model: AppModel, setupWindow: SetupWindowController) -> DeveloperTools {
        let developer = DeveloperTools(responsiveness: responsiveness)
        developer.raiseSignal = { [weak model] in model?.raiseSignal($0) }
        developer.closeSignal = { [weak model] in model?.clearActiveSignal() }
        developer.restyleSignal = { [weak model] in
            // Ein offenes Signal sofort in der neuen Form zeigen.
            guard let model, let signal = model.activeSignal else { return }
            model.clearSignal(signal.id)
            model.raiseSignal(signal)
        }
        developer.hookEventsText = { [weak self] in self?.coordinator?.recentEventsText() ?? "" }
        developer.nowPlayingText = { [weak self] in self?.music?.rawDataText() ?? "" }
        developer.showWelcome = { [weak setupWindow] in setupWindow?.showWithIntro() }
        developer.resetApp = { [weak self, weak model] in
            guard let model, AppResetter.confirm() else { return }
            AppResetter.resetAndRelaunch(settingsStore: model.settingsStore) { self?.coordinator?.stop() }
        }
        return developer
    }
}
