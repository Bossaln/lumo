import AppKit
import NotchaiCore
import ServiceManagement
import SwiftUI

/// Verwaltet das Einstellungsfenster und den Anmeldedienst von macOS.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var settingsStore: SettingsStore?
    private var shelfStore: ShelfStore?
    private var setup: SetupController?
    private var updates: UpdateController?
    private var openAssistant: () -> Void = {}
    private var developer = DeveloperTools()
    private var tryOut: () -> Void = {}
    private var music = MusicSettingsActions()
    private var window: NSWindow?
    /// Status des Anmeldeobjekts, gelesen beim Öffnen und nach jeder Änderung. Jede Abfrage geht an einen anderen
    /// Prozess; im Rumpf einer Ansicht würde sie bei jedem Neuzeichnen laufen.
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    func configure(settingsStore: SettingsStore, shelfStore: ShelfStore, setup: SetupController, updates: UpdateController,
                   developer: DeveloperTools, openAssistant: @escaping () -> Void, tryOut: @escaping () -> Void,
                   music: MusicSettingsActions) {
        self.settingsStore = settingsStore
        self.shelfStore = shelfStore
        self.setup = setup
        self.updates = updates
        self.developer = developer
        self.openAssistant = openAssistant
        self.tryOut = tryOut
        self.music = music
    }

    /// Fenstertitel in der aktuellen Sprache (nach einem Sprachwechsel).
    func relocalize() {
        window?.title = L("notchai-Einstellungen")
    }

    /// Das Einstellungsfenster ist gerade zu sehen.
    var isVisible: Bool { window?.isVisible == true }

    func show() {
        guard let settingsStore, let shelfStore, let setup, let updates else { return }
        refreshLaunchAtLoginSetting()

        if window == nil {
            // Wie die Systemeinstellungen: Die Seitenleiste reicht bis unter die Ampel, ohne sichtbaren Titel.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L("notchai-Einstellungen")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.contentView = MeasuredHostingView(name: "SettingsView.layout", rootView: SettingsView(
                settingsStore: settingsStore,
                shelfStore: shelfStore,
                windowController: self,
                setup: setup,
                updates: updates,
                openAssistant: openAssistant,
                developer: developer,
                tryOut: tryOut,
                music: music
            ))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Versucht die Änderung und gibt einen deutschen Hinweis für die Ansicht zurück.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            try LoginItemRegistration.perform(
                enabled: enabled,
                register: { try SMAppService.mainApp.register() },
                unregister: { try SMAppService.mainApp.unregister() }
            )
        } catch {
            refreshLaunchAtLoginSetting()
            return "Start beim Anmelden konnte nicht geändert werden: \(error.localizedDescription)"
        }

        refreshLaunchAtLoginSetting()
        switch loginItemStatus {
        case .requiresApproval:
            return L("Bitte notchai unter Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben.")
        case .notFound:
            return L("macOS findet notchai nicht als Anmeldeobjekt.")
        case .notRegistered, .enabled:
            return nil
        @unknown default:
            return L("macOS meldet einen unbekannten Status für das Anmeldeobjekt.")
        }
    }

    /// Eigener Verlauf für ⌘Z/⇧⌘Z in den Textfeldern des Fensters.
    private let undoManager = UndoManager()

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func refreshLaunchAtLoginSetting() {
        guard let settingsStore else { return }
        let status = SMAppService.mainApp.status
        loginItemStatus = status
        let enabled = status == .enabled || status == .requiresApproval
        // Nur bei Änderung schreiben: Jede Änderung zeichnet alles neu, was Einstellungen liest (auch die Notch).
        if settingsStore.settings.launchAtLogin != enabled { settingsStore.settings.launchAtLogin = enabled }
    }
}

/// Was die Seite „Musik“ der Einstellungen von der laufenden App braucht.
@MainActor
struct MusicSettingsActions {
    /// Zeigt in der echten Notch, wie ein neuer Titel aussieht.
    var previewTrackChange: () -> Void = {}
    /// Für den Hinweis, ob echter Ton ankommt.
    var visualizer: MusicVisualizer?
}

/// Hosting-View, die misst, wie lange SwiftUI für ihre Ansicht rechnet (Seite „Entwickler“ › Reaktion).
final class MeasuredHostingView<Content: View>: NSHostingView<Content> {
    private var name = ""

    convenience init(name: String, rootView: Content) {
        self.init(rootView: rootView)
        self.name = name
    }

    override func layout() {
        MainThreadWork.measure(name) { super.layout() }
    }
}
