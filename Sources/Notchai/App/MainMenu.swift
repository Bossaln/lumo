import AppKit

/// Kleines deutsches Hauptmenü. macOS zeigt es nur, solange notchai `.regular` ist (Einstellungsfenster offen);
/// im Menüleisten-Modus (`.accessory`) bleibt es unsichtbar, das Statusmenü ist davon unabhängig.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "notchai")
        app.addItem(withTitle: "notchai beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        // Standard-Aktionen gehen an das aktive Textfeld (Responder-Kette).
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Fenster")
        window.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        return main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
