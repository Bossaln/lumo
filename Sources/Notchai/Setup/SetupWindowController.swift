import AppKit
import NotchaiCore
import SwiftUI

/// Fenster des Einrichtungs-Assistenten. Beim ersten Start kommt vorher das Leuchten (`IntroGlowController`);
/// solange der Assistent offen ist, leuchtet die Notch. Im Menü „Einrichtung …“ öffnet er sich ohne Leuchten.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let setup: SetupController
    private let model: AppModel
    private let intro = IntroGlowController()
    private var window: NSWindow?

    init(setup: SetupController, model: AppModel) {
        self.setup = setup
        self.model = model
    }

    private var settingsStore: SettingsStore { model.settingsStore }

    /// Wie beim ersten Start: Der Bildschirm leuchtet auf, das Leuchten zieht sich in die Notch, dann der Assistent.
    func showWithIntro() {
        let settings = settingsStore.settings
        let colors = [Color(hex: settings.claudeColorHex), Color(.sRGB, red: 1.0, green: 0.36, blue: 0.62),
                      Color(.sRGB, red: 0.62, green: 0.40, blue: 1.0), Color(hex: settings.codexColorHex),
                      Color(.sRGB, red: 0.30, green: 0.90, blue: 0.85)]
        intro.play(screen: model.screen, colors: colors) { [weak self] in self?.show() }
    }

    func show() {
        setup.refresh()
        model.setupGlow = true
        if window == nil {
            // Wie die Systemeinstellungen: Die farbige Leiste reicht bis unter die Ampel.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = L("notchai einrichten")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        // Jedes Öffnen beginnt beim ersten Schritt.
        window?.contentView = NSHostingView(rootView: SetupAssistantView(
            setup: setup, settingsStore: settingsStore,
            tryOut: { [weak model] in model?.raiseSignal(SignalDemo.preview) },
            finish: { [weak self] in self?.finish() }))
        window?.center()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func finish() {
        settingsStore.settings.setupCompleted = true
        model.setupGlow = false
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Auch Schließen über den roten Knopf zählt als erledigt; der Assistent ist im Menü jederzeit erreichbar.
        settingsStore.settings.setupCompleted = true
        model.setupGlow = false
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== window && $0.styleMask.contains(.titled) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
