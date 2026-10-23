import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // Sichtbar nur, solange das Einstellungsfenster die App nach vorn holt (⌘W, ⌘C/⌘V/⌘A …).
    app.mainMenu = MainMenu.make()
    app.run()
}
