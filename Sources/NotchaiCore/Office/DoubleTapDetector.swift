import Foundation

/// Erkennt zwei schnelle Tastendrücke hintereinander (zweimal rechte ⌘ öffnet das Büro).
public struct DoubleTapDetector: Sendable {
    public let window: TimeInterval
    private var last: Date?

    public init(window: TimeInterval = 0.4) {
        self.window = window
    }

    /// Meldet einen Druck; `true`, wenn er den vorigen innerhalb des Zeitfensters ergänzt.
    public mutating func register(at date: Date) -> Bool {
        if let last, date.timeIntervalSince(last) < window {
            self.last = nil
            return true
        }
        last = date
        return false
    }

    public mutating func reset() {
        last = nil
    }
}

/// Wertet die Tastenereignisse für „zweimal eine Sondertaste“ aus (rechte ⌘ öffnet das Büro, ⌃ eine Schnellnotiz).
/// Zählt nur ein kurzes Antippen der Taste allein: Tastenkürzel wie ⌘C, langes Halten und andere Sondertasten
/// setzen die Erkennung zurück.
public struct ModifierTapTracker: Sendable {
    public struct Key: Sendable {
        /// Tastencode → geräteabhängiges Bit dieser Taste in `NSEvent.modifierFlags.rawValue`.
        let bits: [UInt16: UInt64]
        /// Geräteunabhängiges Bit der Sondertaste.
        let flag: UInt64

        /// Nur die rechte ⌘-Taste.
        public static let rightCommand = Key(bits: [54: 0x10], flag: 1 << 20)
        /// Linke oder rechte ⌃-Taste.
        public static let control = Key(bits: [59: 0x01, 62: 0x2000], flag: 1 << 18)
    }

    /// Geräteunabhängige Sondertasten (⇪ ⇧ ⌃ ⌥ ⌘ Fn).
    static let modifierMask: UInt64 = 0xFFFF_0000
    /// Länger gehalten ist kein Antippen mehr.
    static let maxHold: TimeInterval = 0.35

    public let key: Key
    private var pressedAt: Date?
    private var detector = DoubleTapDetector()

    public init(key: Key) {
        self.key = key
    }

    /// Meldet ein `flagsChanged`-Ereignis; `true`, wenn damit die Taste zweimal angetippt wurde.
    public mutating func flagsChanged(keyCode: UInt16, flags: UInt64, at date: Date) -> Bool {
        guard let bit = key.bits[keyCode] else {
            interrupt()
            return false
        }
        if flags & bit != 0 {
            // Gedrückt: zählt nur, wenn außer dieser Sondertaste nichts gehalten wird.
            pressedAt = flags & Self.modifierMask == key.flag ? date : nil
            if pressedAt == nil { detector.reset() }
            return false
        }
        defer { pressedAt = nil }
        guard let pressedAt, date.timeIntervalSince(pressedAt) <= Self.maxHold else {
            detector.reset()
            return false
        }
        return detector.register(at: date)
    }

    /// Eine andere Taste wurde gedrückt (etwa das C in ⌘C).
    public mutating func keyDown() {
        interrupt()
    }

    private mutating func interrupt() {
        pressedAt = nil
        detector.reset()
    }
}

/// Zweimal rechte ⌘ (Büro).
public struct RightCommandTapTracker: Sendable {
    private var tracker = ModifierTapTracker(key: .rightCommand)

    public init() {}

    public mutating func flagsChanged(keyCode: UInt16, flags: UInt64, at date: Date) -> Bool {
        tracker.flagsChanged(keyCode: keyCode, flags: flags, at: date)
    }

    public mutating func keyDown() {
        tracker.keyDown()
    }
}
