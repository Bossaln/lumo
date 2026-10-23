import AppKit
import NotchaiCore

/// Menüleisten-Symbol mit Menü und optionalem "Wartet"-Punkt.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var mainInsertIndex = 0
    /// Punkt oben rechts am Symbol. Eine eigene kleine Ebene: Das Symbol bleibt ein Vorlagenbild, das macOS selbst
    /// in der Farbe der Menüleiste zeichnet, und beim Klicken muss nichts neu gemalt werden.
    private let dot = NSView()
    private var settingsAction: @MainActor () -> Void = {}
    /// Einträge samt ihrem Titel; nach einem Sprachwechsel bekommen sie ihn neu (`relocalize`).
    private var titles: [(item: NSMenuItem, title: () -> String)] = []
    /// Meldet, wie lange das Menü nach dem Klick zum Öffnen brauchte (Seite „Entwickler“).
    var onMenuOpen: ((TimeInterval) -> Void)?

    override init() {
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "notchai")
            image?.isTemplate = true
            button.image = image
            installDot(on: button)
        }
        buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() {
        let settings = NSMenuItem(title: L("Einstellungen …"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        titles.append((settings, { L("Einstellungen …") }))
        mainInsertIndex = menu.items.count
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("notchai beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        titles.append((quit, { L("notchai beenden") }))
    }

    private func installDot(on button: NSStatusBarButton) {
        let rgb = ColorHex.parse("#E0764A") ?? RGB(r: 0.88, g: 0.46, b: 0.29)
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1).cgColor
        dot.layer?.cornerRadius = 3
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(dot)
        // Oben rechts am 18-pt-Symbol, das mittig im Knopf steht.
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -6),
        ])
    }

    func setSettingsAction(_ action: @escaping @MainActor () -> Void) {
        settingsAction = action
    }

    @objc private func openSettings() {
        settingsAction()
    }

    /// Hängt einen Eintrag in den Hauptteil des Menüs. Die Entwickler-Werkzeuge stehen in den Einstellungen.
    func addMenuItem(_ item: NSMenuItem) {
        menu.insertItem(item, at: mainInsertIndex)
        mainInsertIndex += 1
    }

    /// Bequemer Weg für Einträge, die nur eine Closure ausführen. `title` liefert den Titel in der aktuellen
    /// Sprache. Gibt den Eintrag zurück, damit sich sein Titel später ändern lässt (etwa „Update installieren …“).
    @discardableResult
    func addMenuItem(_ title: @escaping () -> String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title(), handler: action)
        addMenuItem(item)
        titles.append((item, title))
        return item
    }

    /// Alle Titel neu, nach einem Wechsel der Sprache.
    func relocalize() {
        for entry in titles { entry.item.title = entry.title() }
    }

    /// Zeigt oder versteckt den kleinen Punkt über dem Symbol.
    func setWaitingDot(_ visible: Bool) {
        dot.isHidden = !visible
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Zeitstempel der Ereignisse zählen wie `systemUptime` ab dem Start des Macs.
        guard let event = NSApp.currentEvent else { return }
        onMenuOpen?(ProcessInfo.processInfo.systemUptime - event.timestamp)
    }
}

/// Menüeintrag, der beim Auswählen eine Closure ausführt.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("nicht unterstützt") }

    @objc private func run() {
        MainActor.assumeIsolated { handler() }
    }
}
