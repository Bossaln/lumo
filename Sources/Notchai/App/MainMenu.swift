import AppKit

/// Kleines deutsches Hauptmenü. macOS zeigt es nur, solange notchai `.regular` ist (Einstellungsfenster offen);
/// im Menüleisten-Modus (`.accessory`) bleibt es unsichtbar, das Statusmenü ist davon unabhängig.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "notchai")
        app.addItem(withTitle: L("notchai beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        // Standard-Aktionen gehen an das aktive Textfeld (Responder-Kette).
        let edit = NSMenu(title: L("Bearbeiten"))
        edit.addItem(withTitle: L("Widerrufen"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("Wiederholen"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Ausschneiden"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Kopieren"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Einsetzen"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Alles auswählen"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: L("Fenster"))
        window.addItem(withTitle: L("Schließen"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        return main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
