import Foundation

/// Sondertasten der Tastatur, die macOS als „System-definierte“ Ereignisse schickt (Lautstärke, Helligkeit,
/// Tastaturlicht, Wiedergabe). Die Zahlen sind die von macOS (`NX_KEYTYPE_*`).
public enum MediaKey: Int, Equatable, Sendable {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case play = 16, next = 17, previous = 18, fast = 19, rewind = 20
    case illuminationUp = 21, illuminationDown = 22, illuminationToggle = 23

    /// Tasten, deren Einblendung lumo übernimmt; alles andere (Wiedergabe) bleibt bei macOS.
    public var isHandledByLumo: Bool {
        switch self {
        case .soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown, .illuminationUp, .illuminationDown, .illuminationToggle: true
        case .play, .next, .previous, .fast, .rewind: false
        }
    }
}

public struct MediaKeyPress: Equatable, Sendable {
    public var key: MediaKey
    public var down: Bool
    public var isRepeat: Bool

    public init(key: MediaKey, down: Bool, isRepeat: Bool) {
        self.key = key
        self.down = down
        self.isRepeat = isRepeat
    }
}

public enum MediaKeys {
    /// Untertyp der Ereignisse mit Sondertasten (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`).
    public static let auxControlSubtype = 8

    /// Liest Taste, Richtung und Wiederholung aus `data1` eines System-definierten Ereignisses:
    /// Taste in den oberen 16 Bit, darunter 0x0A für gedrückt und 0x0B für losgelassen, Bit 0 für Wiederholung.
    public static func decode(subtype: Int, data1: Int) -> MediaKeyPress? {
        guard subtype == auxControlSubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        guard let key = MediaKey(rawValue: code) else { return nil }
        let state = (flags & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        return MediaKeyPress(key: key, down: state == 0x0A, isRepeat: flags & 0x1 == 1)
    }

    /// Stufen wie bei macOS: 16 pro Weg, mit ⌥⇧ 64 (feine Stufen).
    public static func step(fine: Bool) -> Double {
        fine ? 1.0 / 64 : 1.0 / 16
    }

    /// Nächster Wert nach einem Tastendruck: auf das Raster der Stufe gelegt, damit sich nichts aufsummiert,
    /// und auf 0…1 begrenzt.
    public static func adjusted(_ level: Double, up: Bool, fine: Bool) -> Double {
        let step = step(fine: fine)
        let steps = (level / step).rounded(.toNearestOrAwayFromZero) + (up ? 1 : -1)
        return min(max(steps * step, 0), 1)
    }
}
