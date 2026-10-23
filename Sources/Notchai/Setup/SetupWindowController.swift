import AppKit
import NotchaiCore
import SwiftUI

/// Fenster des Einrichtungs-Assistenten. Öffnet sich beim ersten Start und über das Menü „Einrichtung …“.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let setup: SetupController
    private let settingsStore: SettingsStore
    private var window: NSWindow?

    init(setup: SetupController, settingsStore: SettingsStore) {
        self.setup = setup
        self.settingsStore = settingsStore
    }

    func show() {
        setup.refresh()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "notchai einrichten"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        // Jedes Öffnen beginnt beim ersten Schritt.
        window?.contentView = NSHostingView(rootView: SetupAssistantView(setup: setup, finish: { [weak self] in self?.finish() }))
        window?.center()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        settingsStore.settings.setupCompleted = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Auch Schließen über den roten Knopf zählt als erledigt; der Assistent ist im Menü jederzeit erreichbar.
        settingsStore.settings.setupCompleted = true
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== window && $0.styleMask.contains(.titled) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
