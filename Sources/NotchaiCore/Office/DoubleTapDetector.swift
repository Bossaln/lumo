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

/// Wertet die Tastenereignisse für „zweimal rechte ⌘“ aus. Zählt nur ein kurzes Antippen der rechten ⌘-Taste
/// allein: Tastenkürzel wie ⌘C, langes Halten und andere Sondertasten setzen die Erkennung zurück.
public struct RightCommandTapTracker: Sendable {
    public static let keyCode: UInt16 = 54
    /// Geräteabhängiges Bit der rechten ⌘-Taste in `NSEvent.modifierFlags.rawValue`.
    static let rightCommandBit: UInt64 = 0x10
    static let commandFlag: UInt64 = 1 << 20
    /// Geräteunabhängige Sondertasten (⇪ ⇧ ⌃ ⌥ ⌘ Fn).
    static let modifierMask: UInt64 = 0xFFFF_0000
    /// Länger gehalten ist kein Antippen mehr.
    static let maxHold: TimeInterval = 0.35

    private var pressedAt: Date?
    private var detector = DoubleTapDetector()

    public init() {}

    /// Meldet ein `flagsChanged`-Ereignis; `true`, wenn damit zweimal rechte ⌘ angetippt wurde.
    public mutating func flagsChanged(keyCode: UInt16, flags: UInt64, at date: Date) -> Bool {
        guard keyCode == Self.keyCode else {
            interrupt()
            return false
        }
        if flags & Self.rightCommandBit != 0 {
            // Gedrückt: zählt nur, wenn außer ⌘ nichts gehalten wird.
            pressedAt = flags & Self.modifierMask == Self.commandFlag ? date : nil
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
