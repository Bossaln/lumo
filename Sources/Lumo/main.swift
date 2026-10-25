import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // Das Hauptmenü (⌘W, ⌘C/⌘V/⌘A …) setzt der AppDelegate, sobald die Sprache feststeht.
    app.run()
}
