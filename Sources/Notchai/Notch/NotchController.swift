import AppKit
import NotchaiCore
import Observation
import SwiftUI

/// Hält das Notch-Panel auf dem Bildschirm, auf dem gerade gearbeitet wird, und steuert Hover und Klickdurchlass.
/// Externe Bildschirme bekommen eine gedachte Notch (`ExternalNotch`); die anderen zeigen solange eine ruhende Kopie
/// (`ExternalNotchMirror`). Lebt so lange wie die App.
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
    /// Island-Breite, für die das Panel gerade sitzt.
    private var positionedSideWidth: Double?
    /// Werden gerade Dateien gezogen (aus dem Finder, Mail …)?
    private var fileDrag = FileDragTracker()
    /// Die gezogenen Dateien sind nah an der Notch; die Ablage ist dafür aufgeklappt.
    private var fileDragNearNotch = false
    /// Letzter Blick in den Drag-Zwischenspeicher; jeder Blick ist eine Anfrage an einen anderen Prozess.
    private var lastDragCheck = Date.distantPast
    /// Bildschirme, die eine Notch haben (echt oder gedacht), aus `NSScreen.screens`.
    private var candidates: [ScreenInfo] = []
    /// Ruhende Kopien auf externen Bildschirmen, auf denen die Notch gerade nicht ist (nach Bildschirm-Rahmen).
    private var mirrors: [String: ExternalNotchMirror] = [:]

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(rootView: NotchRootView(model: model))
        panel.keyPolicy = { [weak model] in model?.acceptsKeyboard ?? false }

        // Globale Maus-Monitore brauchen keine Bedienungshilfen-Berechtigung. Gedrückte Maustaste und Ziehen
        // zählen mit: So merkt die Notch, wenn jemand Dateien zu ihr zieht (Reiter „Ablage“).
        let mouse: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type, inNotchai: false) }
        }) {
            observers.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type, inNotchai: true) }
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
        observeExternalNotch()
        updateScreen()
    }

    /// Liest die Bildschirme neu (angeschlossen, entfernt, Auflösung, Einstellung) und setzt die Notch auf den
    /// richtigen; ohne jeden Notch-Bildschirm wird das Panel ausgeblendet.
    private func updateScreen() {
        let external = model.settingsStore.settings.externalNotch
        candidates = NSScreen.screens.compactMap { screen in
            if screen.safeAreaInsets.top > 0 { return Self.screenInfo(screen) }
            guard external else { return nil }
            return ExternalNotch.virtualScreen(frame: screen.frame, menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
        }
        moveNotch(force: true)
    }

    /// Die Notch folgt dem Zeiger auf den Bildschirm, auf dem gearbeitet wird; so erscheinen Signale dort. Offen
    /// (Signal, Panel, Hover) bleibt sie, wo sie ist, damit nichts unter dem Zeiger wegspringt.
    private func moveNotch(force: Bool = false) {
        let pointer = NSEvent.mouseLocation
        let current = model.screen.flatMap { info in candidates.first { $0.frame == info.frame } }
        let busy = model.notch.mode != .idle || isHovering || pointerInside
        let underPointer = candidates.first { $0.frame.insetBy(dx: 0, dy: -2).contains(pointer) }
        let target: ScreenInfo? = if let current, busy || underPointer == nil {
            current
        } else {
            underPointer ?? candidates.first { !$0.isVirtual } ?? candidates.first
        }
        guard force || target != model.screen else { return }
        if force { rebuildMirrors() }
        // Beim Wechsel steht die Form sofort fertig da: Aus der Form des anderen Bildschirms heranzuwachsen sähe
        // wie ein Wackeln aus.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { model.screen = target }
        refreshPanelPosition()
    }

    /// Mit mehreren Notch-Bildschirmen zeichnet je Bildschirm eine ruhende Kopie den Ruhezustand, dauerhaft und
    /// unter der echten Notch. Wechselt die Notch den Bildschirm, bleibt das Bild damit unverändert. Am MacBook zeigt
    /// die Kopie die eingeklappte Musik neben der Kamera, falls sie läuft.
    private func rebuildMirrors() {
        for mirror in mirrors.values { mirror.orderOut(nil) }
        mirrors = [:]
        model.mirrorsDrawIdle = candidates.count > 1
        guard model.mirrorsDrawIdle else { return }
        for screen in candidates {
            let mirror = ExternalNotchMirror(model: model, screen: screen)
            mirror.orderFrontRegardless()
            mirrors[Self.key(screen)] = mirror
        }
        // Die echte Notch liegt darüber.
        panel.orderFrontRegardless()
    }

    private static func key(_ screen: ScreenInfo) -> String {
        NSStringFromRect(screen.frame)
    }

    /// Schalter „Notch auf externen Bildschirmen“: sofort umsetzen.
    private func observeExternalNotch() {
        withObservationTracking {
            _ = model.settingsStore.settings.externalNotch
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateScreen()
                self?.observeExternalNotch()
            }
        }
    }

    /// Beobachtet die Island-Breite, damit das Panel bei einem Reglerwechsel mitwächst. Gemeldet wird jede
    /// Änderung der Einstellungen; das Panel rückt nur, wenn sich die Breite wirklich geändert hat.
    private func observeIslandSideWidth() {
        withObservationTracking {
            _ = model.settingsStore.settings.islandSideWidth
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if model.settingsStore.settings.islandSideWidth != positionedSideWidth { refreshPanelPosition() }
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
        let sideWidth = model.settingsStore.settings.islandSideWidth
        positionedSideWidth = sideWidth
        MainThreadWork.measure("Notch.position") {
            panel.position(around: notch, islandSideWidth: CGFloat(sideWidth))
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private static func screenInfo(_ screen: NSScreen) -> ScreenInfo {
        ScreenInfo(frame: screen.frame, topInset: screen.safeAreaInsets.top,
                   leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                   rightAuxWidth: screen.auxiliaryTopRightArea?.width)
    }

    private func handleMouse(_ type: NSEvent.EventType, inNotchai: Bool) {
        // Wechselt der Zeiger den Bildschirm, kommt die Notch mit (nur mit mehreren Notch-Bildschirmen).
        if candidates.count > 1, type == .mouseMoved || type == .leftMouseDragged { moveNotch() }
        switch type {
        case .leftMouseDown:
            // Klicks in notchai selbst (Menüleiste, Notch) fragen den Drag-Zwischenspeicher nicht; jede Frage geht an
            // einen anderen Prozess und hielte das Menü auf.
            let watch = !inNotchai && model.settingsStore.settings.shelfEnabled
            fileDrag.mouseDown(changeCount: watch ? NSPasteboard(name: .drag).changeCount : 0, insideNotchai: !watch)
        case .leftMouseDragged:
            trackFileDrag()
            // Wer ein Fenster oder Text zieht, soll die Notch nicht aufklappen; nur Dateien öffnen sie.
            if fileDrag.isDraggingFiles { updatePointer() }
        case .leftMouseUp:
            if fileDrag.mouseUp() { fileDragEnded() }
        default:
            updatePointer()
        }
    }

    /// Kommen gezogene Dateien der Notch nahe, klappt sie zur Ablage auf und zeigt AirDrop und Ablage als Ziele.
    private func trackFileDrag() {
        guard model.settingsStore.settings.shelfEnabled, model.screen != nil else { return }
        if !fileDrag.isDraggingFiles {
            guard fileDrag.isWatching else { return }
            let now = Date()
            guard now.timeIntervalSince(lastDragCheck) >= 0.08 else { return }
            lastDragCheck = now
            let board = NSPasteboard(name: .drag)
            let hasFiles = board.types?.contains(.fileURL) == true
            guard fileDrag.dragged(changeCount: board.changeCount, hasFiles: hasFiles) else { return }
        }
        let near = model.visibleFrame().map { Self.contains(NotchGeometry.dropZone(around: $0), NSEvent.mouseLocation) } ?? false
        if near, !fileDragNearNotch { model.send(.fileDragEntered) }
        fileDragNearNotch = near
    }

    /// Losgelassen (abgelegt oder irgendwo anders): Die Ablage zeigt danach wieder ihre Dateien.
    private func fileDragEnded() {
        fileDragNearNotch = false
        // Erst nach dem Ablegen umschalten, sonst verschwänden die Ziele unter der fallenden Datei.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.model.send(.fileDragEnded)
        }
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

    /// Zweimal ⌃: Die Notch öffnet den Reiter „Notizen“ und bekommt die Tastatur, ohne dass notchai die vordere
    /// App ablöst. Gespeichert (↩) oder abgebrochen (Escape, Klick woandershin) klappt sie wieder zu.
    func openNote() {
        guard model.screen != nil else { return }
        model.send(.noteShortcut(pointerInside: pointerInside))
        guard model.notch.isWritingNote else { return }
        panel.makeKey()
        // Ohne Tastatur ließe sich nichts schreiben; dann gleich wieder zu.
        guard panel.isKeyWindow else {
            model.send(.editingEnded)
            return
        }
        focusNoteField()
    }

    /// Setzt den Cursor ins Notizfeld, sobald SwiftUI es gezeichnet hat (der Reiter kommt eben erst ins Bild).
    private func focusNoteField(attempt: Int = 0) {
        if let field = Self.editableText(in: panel.contentView), panel.makeFirstResponder(field) { return }
        guard attempt < 8, model.notch.isWritingNote else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.focusNoteField(attempt: attempt + 1)
        }
    }

    /// Erstes Eingabefeld in der Ansicht (SwiftUI baut Textfelder aus AppKit-Textfeldern bzw. -Textansichten).
    private static func editableText(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        if let text = view as? NSTextView, text.isEditable { return text }
        for child in view.subviews {
            if let found = editableText(in: child) { return found }
        }
        return nil
    }

    /// Liegt der Zeiger über ✕/✓ einer sichtbaren Freigabe in der Island? Eine Frage hat dort nur den Pfeil zum
    /// Aufklappen; über ihm klappt Hover direkt zum Banner mit den Antworten auf.
    private func isOverIslandButtons(_ point: CGPoint) -> Bool {
        guard model.notch.mode == .signal(.island), model.activeSignal?.kind == .permission,
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
        // Notiz über zweimal ⌃: erst zuklappen, dann (unsichtbar hinter der Kamera) die Tastatur abgeben.
        if model.notch.isWritingNote {
            model.send(.editingEnded)
            if model.notch.mode == .idle {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.releaseKeyboard()
                }
                return true
            }
        }
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
