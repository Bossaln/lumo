import AppKit
import NotchaiCore
import Observation
import SwiftUI

/// Ob das große Büro gerade gezeigt wird (steuert die Animation im Fenster).
@MainActor @Observable
final class OfficePresentation {
    var isShown = false
}

/// Das große Büro: wächst unter der Notch heraus (Größe mal `officeScale`), höchstens so groß
/// wie der Bildschirm. Schließt per Escape, ✕, Klick daneben oder auf die Notch, beim Wechsel in eine andere App
/// und nach einem Klick auf eine Figur (deren Fenster kommt dann nach vorn).
@MainActor
final class OfficeWindowController {
    /// Rand für den Schatten links, rechts und unten.
    private static let shadowMargin: CGFloat = 36
    private static let escapeKeyCode: UInt16 = 53

    private let settingsStore: SettingsStore
    private let director: OfficeDirector
    private let presentation = OfficePresentation()
    private var panel: OfficePanel?
    private var monitors: [Any] = []
    private var observers: [Any] = []
    private var hideTask: Task<Void, Never>?

    init(settingsStore: SettingsStore, director: OfficeDirector) {
        self.settingsStore = settingsStore
        self.director = director
    }

    var isOpen: Bool { presentation.isShown }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard settingsStore.settings.officeEnabled, !isOpen else { return }
        hideTask?.cancel()
        hideTask = nil
        let panel = self.panel ?? makePanel()
        guard let screen = Self.targetScreen() else { return }
        let notch = Self.notchCenterX(screen)
        let topInset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : screen.frame.maxY - screen.visibleFrame.maxY
        let geometry = OfficeWindowGeometry.frame(screen: screen.frame, topInset: topInset, centerX: notch,
                                                  officeScale: settingsStore.settings.officeScale,
                                                  backingScale: screen.backingScaleFactor)
        let m = Self.shadowMargin
        let frame = geometry.frame
        panel.contentFrame = CGRect(x: m, y: 0, width: frame.width, height: frame.height)
        panel.setFrame(NSRect(x: frame.minX - m, y: frame.minY - m, width: frame.width + 2 * m, height: frame.height + m),
                       display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        presentation.isShown = true
        installMonitors()
    }

    func close() {
        guard isOpen else { return }
        presentation.isShown = false
        removeMonitors()
        // Erst nach der Animation ausblenden; dann bekommt die vorige App die Tastatur zurück.
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> OfficePanel {
        let view = OfficeWindowView(director: director, presentation: presentation, margin: Self.shadowMargin,
                                    close: { [weak self] in self?.close() })
        let panel = OfficePanel(rootView: view)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        self.panel = panel
        return panel
    }

    private func installMonitors() {
        removeMonitors()
        // Klick in eine andere App (globale Maus-Monitore brauchen keine Berechtigung).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            monitors.append(global)
        }
        // Klick auf die Notch oder in den Schattenrand; Escape im Büro.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            // Nur die Werte gehen in den MainActor, nicht das Ereignis selbst.
            let (type, keyCode, window, location) = (event.type, event.keyCode, event.window, event.locationInWindow)
            let consumed = MainActor.assumeIsolated {
                self?.handleLocal(type, keyCode: keyCode, window: window, location: location) ?? false
            }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }
    }

    /// `true`, wenn das Ereignis damit erledigt ist.
    private func handleLocal(_ type: NSEvent.EventType, keyCode: UInt16, window: NSWindow?, location: CGPoint) -> Bool {
        guard let panel else { return false }
        if type == .keyDown {
            guard keyCode == Self.escapeKeyCode, window === panel else { return false }
            close()
            return true
        }
        if window !== panel {
            close()
            return false
        }
        // Im Panel, aber neben dem Bild (Schattenrand): wie ein Klick daneben.
        let flipped = CGPoint(x: location.x, y: panel.frame.height - location.y)
        guard !panel.contentFrame.contains(flipped) else { return false }
        close()
        return true
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
    }

    /// Bildschirm mit Notch, sonst der Hauptbildschirm.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Mitte der Notch (zwischen den beiden Menüleisten-Hälften), sonst die Bildschirmmitte.
    private static func notchCenterX(_ screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }
}

/// Randloses, durchsichtiges Panel. Es nimmt die Tastatur (für Escape), ohne notchai zu aktivieren.
final class OfficePanel: NSPanel {
    /// Lage des Bildes im Panel (Ursprung oben links), ohne Schattenrand.
    var contentFrame: CGRect = .zero

    init(rootView: OfficeWindowView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Über normalen Fenstern, unter der Notch.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        let host = OfficeHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Nimmt schon den ersten Klick an (auf eine Figur), obwohl notchai nicht aktiv ist.
private final class OfficeHostingView: NSHostingView<OfficeWindowView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Inhalt des großen Fensters: die Halle mit runden Ecken, Schatten und ✕ beim Darüberfahren.
struct OfficeWindowView: View {
    let director: OfficeDirector
    let presentation: OfficePresentation
    let margin: CGFloat
    let close: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            if presentation.isShown {
                OfficeView(director: director)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    .overlay(alignment: .topTrailing) { closeButton }
                    .shadow(color: Color.black.opacity(0.55), radius: 26, x: 0, y: 14)
                    .onHover { hovering = $0 }
                    .transition(.officeGrow)
            }
        }
        .padding(.horizontal, margin)
        .padding(.bottom, margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(presentation.isShown ? .spring(response: 0.42, dampingFraction: 0.86) : .easeIn(duration: 0.22),
                   value: presentation.isShown)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Büro schließen (Esc)")
        .padding(12)
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

extension AnyTransition {
    /// Das Büro wächst oben mittig aus der Notch und wird dabei scharf; beim Schließen zieht es sich zurück.
    static var officeGrow: AnyTransition {
        .modifier(active: OfficeGrowModifier(progress: 0), identity: OfficeGrowModifier(progress: 1))
    }
}

private struct OfficeGrowModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.18 + 0.82 * progress, y: 0.06 + 0.94 * progress, anchor: .top)
            .blur(radius: (1 - progress) * 14)
            .opacity(min(1, progress * 1.6))
    }
}
