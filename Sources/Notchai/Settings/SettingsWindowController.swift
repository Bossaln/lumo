import AppKit
import NotchaiCore
import ServiceManagement
import SwiftUI

/// Verwaltet das Einstellungsfenster und den Anmeldedienst von macOS.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var settingsStore: SettingsStore?
    private var setup: SetupController?
    private var updates: UpdateController?
    private var openAssistant: () -> Void = {}
    private var window: NSWindow?

    func configure(settingsStore: SettingsStore, setup: SetupController, updates: UpdateController,
                   openAssistant: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.setup = setup
        self.updates = updates
        self.openAssistant = openAssistant
    }

    func show() {
        guard let settingsStore, let setup, let updates else { return }
        refreshLaunchAtLoginSetting()

        if window == nil {
            // Wie die Systemeinstellungen: Die Seitenleiste reicht bis unter die Ampel, ohne sichtbaren Titel.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "notchai-Einstellungen"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.contentView = NSHostingView(rootView: SettingsView(
                settingsStore: settingsStore,
                windowController: self,
                setup: setup,
                updates: updates,
                openAssistant: openAssistant
            ))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Bitte notchai unter Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben."
        case .notFound:
            return "macOS findet notchai nicht als Anmeldeobjekt."
        case .notRegistered, .enabled:
            return nil
        @unknown default:
            return "macOS meldet einen unbekannten Status für das Anmeldeobjekt."
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
        settingsStore.settings.launchAtLogin = status == .enabled || status == .requiresApproval
    }
}
