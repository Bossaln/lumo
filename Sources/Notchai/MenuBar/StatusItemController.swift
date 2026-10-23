import AppKit
import NotchaiCore


/// Menüleisten-Symbol mit Menü und optionalem "Wartet"-Punkt.
@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var mainInsertIndex = 0
    private let dotColor: NSColor
    private var settingsAction: @MainActor () -> Void = {}

    init() {
        let rgb = ColorHex.parse("#E0764A") ?? RGB(r: 0.88, g: 0.46, b: 0.29)
        dotColor = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        setWaitingDot(false)
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        mainInsertIndex = menu.items.count
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "notchai beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    /// Bequemer Weg für Einträge, die nur eine Closure ausführen. Gibt den Eintrag zurück, damit sich
    /// sein Titel später ändern lässt (etwa „Update installieren …“).
    @discardableResult
    func addMenuItem(_ title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        addMenuItem(item)
        return item
    }

    /// Zeigt oder versteckt den kleinen Punkt über dem Symbol.
    func setWaitingDot(_ visible: Bool) {
        statusItem.button?.image = makeImage(withDot: visible)
    }

    private func makeImage(withDot: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "notchai") else { return nil }
        guard withDot else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: 18, height: 18)
        let dotColor = self.dotColor
        let image = NSImage(size: size, flipped: false) { rect in
            // Symbol in Menüleistenfarbe zeichnen, dann Punkt oben rechts.
            let tinted = base.copy() as! NSImage
            tinted.isTemplate = false
            tinted.lockFocus()
            NSColor.labelColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let s = tinted.size
            tinted.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        return image
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
