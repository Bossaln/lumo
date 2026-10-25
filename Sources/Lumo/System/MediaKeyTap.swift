import AppKit
import ApplicationServices
import Foundation
import LumoCore

/// Fängt die Sondertasten (Lautstärke, Helligkeit, Tastaturlicht) ab, bevor macOS sie sieht. Was lumo übernimmt,
/// bekommt macOS nicht mehr, und seine Einblendung in der Bildschirmmitte bleibt aus. Braucht die Berechtigung
/// „Bedienungshilfen“; ohne sie entsteht der Abgriff nicht. Im Mithör-Modus (`listenOnly`) gehen alle Tasten
/// weiter an macOS, lumo erfährt nur davon.
///
/// Der Abgriff läuft auf einem eigenen Thread: Durch ihn gehen alle „System-definierten“ Ereignisse, auch jeder
/// Mausklick, und die dürfen nie auf lumos Hauptthread warten. Entschieden wird dort nur nach der `Policy`;
/// das Stellen der Werte passiert danach auf dem Hauptthread.
final class MediaKeyTap: @unchecked Sendable {
    struct Modifiers: Sendable {
        /// ⌥⇧: feine Stufen.
        var fine: Bool
        /// Nur ⌥: macOS öffnet die passenden Systemeinstellungen; das bleibt bei macOS.
        var optionOnly: Bool
    }

    /// Welche Tasten lumo nimmt und ob es sie macOS wegnimmt.
    struct Policy: Equatable, Sendable {
        var intercept = false
        var keys: Set<MediaKey> = []
    }

    /// Jede Taste aus der `Policy`, auf dem Hauptthread; `consumed` sagt, ob macOS sie nicht mehr bekommt.
    var handler: (@MainActor (MediaKeyPress, Modifiers, _ consumed: Bool) -> Void)?

    private let lock = NSLock()
    private var policy = Policy()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var listenOnly = false

    /// System-definierte Ereignisse (`NX_SYSDEFINED`).
    private static let systemDefined: CGEventType = CGEventType(rawValue: 14)!

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return port != nil
    }

    var isIntercepting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return port != nil && !listenOnly
    }

    func setPolicy(_ policy: Policy) {
        lock.lock()
        self.policy = policy
        lock.unlock()
    }

    /// Legt den Abgriff an; `false`, wenn macOS ihn verweigert (keine Berechtigung).
    @discardableResult
    func start(listenOnly: Bool) -> Bool {
        lock.lock()
        let unchanged = port != nil && self.listenOnly == listenOnly
        lock.unlock()
        if unchanged { return true }
        stop()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                           options: listenOnly ? .listenOnly : .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << Self.systemDefined.rawValue),
                                           callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        lock.lock()
        self.port = port
        self.listenOnly = listenOnly
        lock.unlock()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self?.lock.lock()
            self?.runLoop = CFRunLoopGetCurrent()
            self?.lock.unlock()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.bossaln.lumo.media-keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    func stop() {
        lock.lock()
        let port = port, runLoop = runLoop
        self.port = nil
        self.runLoop = nil
        lock.unlock()
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    /// Auf dem Abgriff-Thread: entscheidet sofort und ohne den Hauptthread.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS schaltet einen Abgriff ab, der zu lange braucht; dann wieder einschalten.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let port = port
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined,
              let press = MediaKeys.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let policy = policy, listenOnly = listenOnly
        lock.unlock()
        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Modifiers(fine: flags.contains(.option) && flags.contains(.shift),
                                  optionOnly: flags.contains(.option) && !flags.contains(.shift))
        guard policy.keys.contains(press.key), !modifiers.optionOnly else { return Unmanaged.passUnretained(event) }
        let consumed = policy.intercept && !listenOnly
        if let handler {
            Task { @MainActor in handler(press, modifiers, consumed) }
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}
