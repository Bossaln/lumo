import AppKit
import ApplicationServices
import Foundation
import LumoCore

/// Fängt die Sondertasten (Lautstärke, Helligkeit, Tastaturlicht) ab, bevor macOS sie sieht. Was lumo übernimmt,
/// bekommt macOS nicht mehr, und seine Einblendung in der Bildschirmmitte bleibt aus. Braucht die Berechtigung
/// „Bedienungshilfen“; ohne sie entsteht der Abgriff nicht. Im Mithör-Modus (`listenOnly`) gehen alle Tasten
/// weiter an macOS, lumo erfährt nur davon.
@MainActor
final class MediaKeyTap {
    struct Modifiers {
        /// ⌥⇧: feine Stufen.
        var fine: Bool
        /// Nur ⌥: macOS öffnet die passenden Systemeinstellungen; das bleibt bei macOS.
        var optionOnly: Bool
    }

    /// Gibt `true` zurück, wenn lumo die Taste verbraucht hat.
    var handler: ((MediaKeyPress, Modifiers) -> Bool)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var listenOnly = false

    /// System-definierte Ereignisse (`NX_SYSDEFINED`).
    private static let systemDefined: CGEventType = CGEventType(rawValue: 14)!

    var isActive: Bool { port != nil }

    /// Legt den Abgriff an; `false`, wenn macOS ihn verweigert (keine Berechtigung).
    @discardableResult
    func start(listenOnly: Bool) -> Bool {
        if isActive, self.listenOnly == listenOnly { return true }
        stop()
        self.listenOnly = listenOnly
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
        }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                           options: listenOnly ? .listenOnly : .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << Self.systemDefined.rawValue),
                                           callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        source = nil
        port = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS schaltet einen Abgriff ab, der zu lange braucht; dann wieder einschalten.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined,
              let press = MediaKeys.decode(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }
        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Modifiers(fine: flags.contains(.option) && flags.contains(.shift),
                                  optionOnly: flags.contains(.option) && !flags.contains(.shift))
        let consumed = handler?(press, modifiers) ?? false
        return consumed && !listenOnly ? nil : Unmanaged.passUnretained(event)
    }
}
