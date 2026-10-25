import CoreGraphics
import Foundation
import ObjectiveC.runtime

/// Helligkeit des eingebauten Bildschirms über Apples DisplayServices (nicht öffentlich, seit Jahren stabil; so
/// stellen auch andere Werkzeuge die Helligkeit). Fehlt etwas davon, bleibt die Helligkeit bei macOS.
@MainActor
final class DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private let get: GetFunction?
    private let set: SetFunction?
    private let canChange: CanChangeFunction?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            get = nil; set = nil; canChange = nil
            return
        }
        get = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFunction.self) }
        set = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFunction.self) }
        canChange = dlsym(handle, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanChangeFunction.self) }
    }

    /// Der eingebaute Bildschirm, sonst der Hauptbildschirm.
    private var display: CGDirectDisplayID {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        if CGGetOnlineDisplayList(8, &displays, &count) == .success,
           let builtin = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtin
        }
        return CGMainDisplayID()
    }

    var isAvailable: Bool {
        guard let get, let set, let canChange else { return false }
        _ = get; _ = set
        return canChange(display)
    }

    var level: Double? {
        guard let get else { return nil }
        var value: Float = 0
        guard get(display, &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    func setLevel(_ level: Double) -> Bool {
        guard let set else { return false }
        return set(display, Float(min(max(level, 0), 1))) == 0
    }
}

/// Tastaturbeleuchtung über Apples CoreBrightness (nicht öffentlich). Ohne beleuchtete Tastatur ist nichts da.
@MainActor
final class KeyboardBacklight {
    private typealias GetFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFunction = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let client: NSObject?
    private let keyboard: UInt64?
    /// Helligkeit vor dem Ausschalten über die Umschalt-Taste.
    private var levelBeforeOff: Double = 0.5

    init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil; keyboard = nil
            return
        }
        let client = type.init()
        self.client = client
        let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        keyboard = ids?.first?.uint64Value
    }

    var isAvailable: Bool { client != nil && keyboard != nil }

    var level: Double? {
        guard let client, let keyboard else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard let method = class_getInstanceMethod(type(of: client), selector) else { return nil }
        let get = unsafeBitCast(method_getImplementation(method), to: GetFunction.self)
        return Double(get(client, selector, keyboard))
    }

    @discardableResult
    func setLevel(_ level: Double) -> Bool {
        guard let client, let keyboard else { return false }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let method = class_getInstanceMethod(type(of: client), selector) else { return false }
        let set = unsafeBitCast(method_getImplementation(method), to: SetFunction.self)
        return set(client, selector, Float(min(max(level, 0), 1)), keyboard)
    }

    /// Umschalt-Taste: aus, oder zurück auf die Helligkeit davor.
    @discardableResult
    func toggle() -> Double? {
        guard let level else { return nil }
        if level > 0 {
            levelBeforeOff = level
            return setLevel(0) ? 0 : nil
        }
        let restored = levelBeforeOff > 0 ? levelBeforeOff : 0.5
        return setLevel(restored) ? restored : nil
    }
}
