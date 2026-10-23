import AppKit
import NotchaiCore
import Observation

/// Hält das Notch-Panel auf dem Notch-Bildschirm und steuert Hover und Klickdurchlass.
/// Lebt so lange wie die App.
@MainActor
final class NotchController {
    /// Kurzes Herausrutschen soll das Panel nicht schließen.
    private static let exitTolerance: Duration = .milliseconds(250)
    private static let escapeKeyCode: UInt16 = 53

    private let model: AppModel
    private let panel: NotchPanel
    private var observers: [Any] = []
    private var enterTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    /// `hoverBegan` wurde gesendet.
    private var isHovering = false
    /// Der Zeiger war zuletzt über der sichtbaren Form, auch wenn `hoverBegan` noch aussteht.
    private var pointerInside = false
    /// Signal, das zuletzt gemeldet wurde; endet es, geht die Tastatur zurück.
    private var shownSignalID: UUID?

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(rootView: NotchRootView(model: model))
        panel.keyPolicy = { [weak model] in model?.acceptsKeyboard ?? false }

        // Globale Maus-Monitore brauchen keine Bedienungshilfen-Berechtigung.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            observers.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            observers.append(local)
        }
        // Escape im Antwortfeld gibt die Tastatur zurück; der Entwurf bleibt.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            let window = event.window
            let consumed = MainActor.assumeIsolated { self?.releaseKeyboard(onEscapeIn: window) ?? false }
            return consumed ? nil : event
        }) {
            observers.append(keys)
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        })
        // Key wird das Panel nur bei einem Klick in ein aufgeklapptes Signal mit Antwortfeld (`keyPolicy`).
        // Solange es key ist, klappt das Signal nicht zu (`NotchState.isEditing`).
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.send(.editingBegan) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.send(.editingEnded) }
        })

        observeIslandSideWidth()
        observeVisibleShape()
        updateScreen()
    }

    /// Liest den Notch-Bildschirm neu; ohne Notch wird das Panel ausgeblendet.
    private func updateScreen() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }.map(Self.screenInfo)
        model.screen = screen
        refreshPanelPosition()
    }

    /// Beobachtet die Island-Breite, damit das Panel bei einem Reglerwechsel mitwächst.
    private func observeIslandSideWidth() {
        withObservationTracking {
            _ = model.settingsStore.settings.islandSideWidth
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshPanelPosition()
                observeIslandSideWidth()
            }
        }
    }

    /// Jede Änderung der sichtbaren Form (Signal kommt oder geht, auch „Fertig“ nach 4 s; Island klappt
    /// auf oder zu; Panel öffnet oder schließt) bewertet Klickdurchlass und Hover neu, auch bei ruhender Maus.
    private func observeVisibleShape() {
        withObservationTracking {
            _ = model.visibleFrame()
            _ = model.islandButtonArea
            _ = model.isScrubbing
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                updatePointer()
                observeVisibleShape()
            }
        }
    }

    private func refreshPanelPosition() {
        guard let screen = model.screen, let notch = NotchGeometry.notchRect(screen) else {
            panel.orderOut(nil)
            return
        }
        panel.position(around: notch, islandSideWidth: CGFloat(model.settingsStore.settings.islandSideWidth))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private static func screenInfo(_ screen: NSScreen) -> ScreenInfo {
        ScreenInfo(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                   leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                   rightAuxWidth: screen.auxiliaryTopRightArea?.width)
    }

    /// Nur über der sichtbaren Form nimmt das Panel Mausereignisse an. Läuft bei jeder Mausbewegung
    /// und bei jeder Änderung der sichtbaren Form.
    private func updatePointer() {
        let location = NSEvent.mouseLocation
        // Beim Spulen gilt der Zeiger als drinnen: Die Notch bleibt offen und bekommt die Maus weiter.
        let inside = model.isScrubbing || (model.visibleFrame().map { Self.contains($0, location) } ?? false)
        // Nur bei Änderung setzen: Jeder Aufruf schickt eine Nachricht an den Fensterserver.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside, isOverIslandButtons(location) {
            // Über ✕/✓ bleibt die Island stehen, damit die Knöpfe unter dem Zeiger bleiben.
            pointerInside = true
            enterTask?.cancel()
            enterTask = nil
            exitTask?.cancel()
            exitTask = nil
        } else if inside {
            pointerInside = true
            exitTask?.cancel()
            exitTask = nil
            guard !isHovering, enterTask == nil else { return }
            let delay = Duration.milliseconds(max(0, model.settingsStore.settings.hoverDelayMs))
            enterTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                enterTask = nil
                isHovering = true
                model.send(.hoverBegan)
            }
        } else {
            enterTask?.cancel()
            enterTask = nil
            // Auch ohne `hoverBegan` – etwa wenn ein Klick die Island aufgeklappt hat, bevor die
            // Hover-Verzögerung um war – fällt die Form nach dem Verlassen zurück.
            guard isHovering || pointerInside, exitTask == nil else { return }
            pointerInside = false
            exitTask = Task { [weak self] in
                try? await Task.sleep(for: Self.exitTolerance)
                guard !Task.isCancelled, let self else { return }
                exitTask = nil
                isHovering = false
                // Wird gerade getippt, bleibt das Signal offen und behält die Tastatur (`NotchState`).
                model.send(.hoverEnded)
                releaseKeyboardIfNeeded()
            }
        }
    }

    /// Wird bei jedem neuen oder geschlossenen Signal aufgerufen. Klickdurchlass und Hover bewertet
    /// `observeVisibleShape()` neu, sobald sich dadurch die Form ändert.
    func signalChanged() {
        let id = model.activeSignal?.id
        defer { shownSignalID = id }
        // Endet das Signal, in dem getippt wurde (abgeschickt, geschlossen, ersetzt), geht die Tastatur
        // zurück, auch wenn das nächste wieder ein Antwortfeld hat: Sonst landete der Rest der Eingabe
        // in der Antwort an einen anderen Agenten.
        if id != shownSignalID {
            releaseKeyboard()
        } else {
            releaseKeyboardIfNeeded()
        }
    }

    /// Liegt der Zeiger über dem Knopfbereich einer sichtbaren Island?
    private func isOverIslandButtons(_ point: CGPoint) -> Bool {
        // Knöpfe zeigt die Island nur, wenn der Agent auf den Besitzer wartet (Freigabe, Frage).
        guard model.notch.mode == .signal(.island), model.activeSignal?.kind.isAwaitingOwner == true,
              let area = model.islandButtonArea else { return false }
        // Panel-Koordinaten (oben links) in Bildschirmkoordinaten (unten links) umrechnen.
        let frame = panel.frame
        let onScreen = CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY,
                              width: area.width, height: area.height)
        return Self.contains(onScreen, point)
    }

    /// Ohne sichtbares Antwortfeld bekommt die vorige App die Tastatur zurück.
    private func releaseKeyboardIfNeeded() {
        guard !model.acceptsKeyboard else { return }
        releaseKeyboard()
    }

    /// Escape im Notch-Panel gibt die Tastatur zurück; `true`, wenn die Taste damit verbraucht ist.
    private func releaseKeyboard(onEscapeIn window: NSWindow?) -> Bool {
        guard window === panel, panel.isKeyWindow else { return false }
        releaseKeyboard()
        return true
    }

    /// Gibt die Tastatur an die vorige App zurück (Escape, Ende des Signals).
    private func releaseKeyboard() {
        guard panel.isKeyWindow else { return }
        // Aus- und wieder Einblenden gibt den Tastaturfokus ab, ohne dass die Notch verschwindet.
        // Dabei meldet das Panel `didResignKey`, und `NotchState` beendet das Tippen.
        panel.orderOut(nil)
        if model.screen != nil { panel.orderFrontRegardless() }
    }

    /// Am oberen Bildschirmrand meldet macOS y == maxY, deshalb zählt die Oberkante mit.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }
}
