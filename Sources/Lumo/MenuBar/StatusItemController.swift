import AppKit
import LumoCore
import SwiftUI

/// Ein Eintrag im Menü der Menüleiste. `title` liefert den Text in der aktuellen Sprache; er lässt sich später ändern
/// (etwa „Update installieren …“).
@MainActor
@Observable
final class StatusMenuEntry: Identifiable {
    let id = UUID()
    var title: String
    let symbol: String
    let shortcut: KeyEquivalent?
    @ObservationIgnored let titleProvider: () -> String
    @ObservationIgnored let action: @MainActor () -> Void

    init(title: @escaping () -> String, symbol: String, shortcut: KeyEquivalent? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title()
        self.titleProvider = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.action = action
    }
}

/// Was das Menü zeigt; die Ansicht beobachtet es.
@MainActor
@Observable
final class StatusMenuModel {
    var entries: [StatusMenuEntry] = []
    var waiting = false
}

/// Menüleisten-Symbol mit optionalem „Wartet“-Punkt. Ein Klick öffnet statt eines macOS-Menüs ein eigenes, schwarzes
/// Menü im Stil der Einstellungen (`StatusMenuView`) direkt unter dem Symbol.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// Punkt oben rechts am Symbol. Eine eigene kleine Ebene: Das Symbol bleibt ein Vorlagenbild, das macOS selbst
    /// in der Farbe der Menüleiste zeichnet, und beim Klicken muss nichts neu gemalt werden.
    private let dot = NSView()
    private let menuModel = StatusMenuModel()
    private var settingsEntry: StatusMenuEntry?
    private var settingsAction: @MainActor () -> Void = {}
    private var panel: StatusMenuPanel?
    private var outsideClickMonitor: Any?
    /// Ein Klick auf das Symbol bei offenem Menü schließt es erst über `resignKey`; danach nicht gleich wieder öffnen.
    private var closedAt: Date?
    /// Meldet, wie lange das Menü nach dem Klick zum Öffnen brauchte (Seite „Entwickler“).
    var onMenuOpen: ((TimeInterval) -> Void)?

    override init() {
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "lumo")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            installDot(on: button)
        }
        let settings = StatusMenuEntry(title: { L("Einstellungen …") }, symbol: "gearshape.fill", shortcut: ",") { [weak self] in
            self?.settingsAction()
        }
        settingsEntry = settings
        menuModel.entries = [settings]
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

    /// Hängt einen Eintrag unter „Einstellungen …“ an. `title` liefert den Titel in der aktuellen Sprache. Gibt den
    /// Eintrag zurück, damit sich sein Titel später ändern lässt.
    @discardableResult
    func addMenuItem(_ title: @escaping () -> String, symbol: String, action: @escaping @MainActor () -> Void) -> StatusMenuEntry {
        let entry = StatusMenuEntry(title: title, symbol: symbol, action: action)
        menuModel.entries.append(entry)
        return entry
    }

    /// Alle Titel neu, nach einem Wechsel der Sprache.
    func relocalize() {
        for entry in menuModel.entries { entry.title = entry.titleProvider() }
    }

    /// Zeigt oder versteckt den kleinen Punkt über dem Symbol.
    func setWaitingDot(_ visible: Bool) {
        dot.isHidden = !visible
        menuModel.waiting = visible
    }

    // MARK: - Menü

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else if closedAt.map({ Date().timeIntervalSince($0) > 0.25 }) ?? true {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let clickedAt = NSApp.currentEvent?.timestamp
        // Jedes Mal neu: Geschlossen soll nichts im Hintergrund weiterlaufen (die Farbschleier bewegen sich).
        let panel = makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 280, height: 260)
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // Unter dem Symbol, linksbündig, aber nie über den rechten Bildschirmrand hinaus.
        let x = min(max(screen.minX + 8, anchor.minX - 6), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        button.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        if let clickedAt { onMenuOpen?(ProcessInfo.processInfo.systemUptime - clickedAt) }
    }

    private func closePanel() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        statusItem.button?.highlight(false)
        guard let panel, panel.isVisible else { return }
        closedAt = Date()
        self.panel = nil
        panel.onResignKey = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }

    private func makePanel() -> StatusMenuPanel {
        let view = StatusMenuView(model: menuModel) { [weak self] entry in
            self?.closePanel()
            // Erst schließen, dann ausführen: Ein neues Fenster soll das Menü nicht verdecken.
            DispatchQueue.main.async { entry.action() }
        } quit: {
            NSApp.terminate(nil)
        }
        let panel = StatusMenuPanel(content: view)
        panel.onResignKey = { [weak self] in self?.closePanel() }
        return panel
    }
}

/// Randloses Fenster für das Menü: schwebt über allem, nimmt Tastatur an (↩, Esc, ⌘,), aktiviert lumo nicht.
private final class StatusMenuPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }
}

/// Das Menü: Kopf mit lumo und Zustand, darunter die Einträge mit Symbol, unten „Beenden“.
private struct StatusMenuView: View {
    let model: StatusMenuModel
    let choose: (StatusMenuEntry) -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Rectangle().fill(Lux.hairline).frame(height: 1).padding(.horizontal, 10)
            VStack(spacing: 2) {
                ForEach(model.entries) { entry in
                    StatusMenuRow(title: entry.title, symbol: entry.symbol, shortcut: entry.shortcut.map { "⌘" + String($0.character) }) {
                        choose(entry)
                    }
                    .commandShortcut(entry.shortcut)
                }
            }
            .padding(6)
            Rectangle().fill(Lux.hairline).frame(height: 1).padding(.horizontal, 10)
            StatusMenuRow(title: L("lumo beenden"), symbol: "power", shortcut: "⌘Q", action: quit)
                .keyboardShortcut("q", modifiers: .command)
                .padding(6)
        }
        .frame(width: 270)
        .background {
            ZStack {
                Color.black
                LuxBackdrop(colors: [Lux.rgb(0.88, 0.46, 0.29), Lux.rgb(0.35, 0.45, 1.0)], intensity: 0.55)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "lumo")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Lux.primary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.waiting ? Lux.rgb(0.88, 0.46, 0.29) : Lux.rgb(0.3, 0.82, 0.45))
                        .frame(width: 6, height: 6)
                    Text(model.waiting ? L("Ein Agent wartet auf dich") : L("Alles ruhig"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Lux.secondary)
                }
            }
        }
    }
}

private extension View {
    /// ⌘ plus `key`, wenn der Eintrag ein Kürzel hat.
    @ViewBuilder
    func commandShortcut(_ key: KeyEquivalent?) -> some View {
        if let key { keyboardShortcut(key, modifiers: .command) } else { self }
    }
}

/// Eine Zeile: Symbol, Titel, rechts das Tastenkürzel. Beim Darüberfahren hell hinterlegt.
private struct StatusMenuRow: View {
    let title: String
    let symbol: String
    let shortcut: String?
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(hovering ? Lux.primary : Lux.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Lux.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Lux.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovering ? 0.10 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
