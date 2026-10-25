import Foundation

/// Wofür die Notch eine Systemanzeige zeigt. Jede Art lässt sich in den Einstellungen einzeln abschalten
/// (`AppSettings.hudHidden`).
public enum SystemIndicatorKind: String, CaseIterable, Codable, Equatable, Sendable {
    case volume, brightness, keyboardBacklight, focus, timer, alarm, microphone, camera, power, audioOutput, capsLock

    public var title: String {
        switch self {
        case .volume: L("Lautstärke")
        case .brightness: L("Helligkeit")
        case .keyboardBacklight: L("Tastaturbeleuchtung")
        case .focus: L("Fokus")
        case .timer: L("Timer")
        case .alarm: L("Wecker")
        case .microphone: L("Mikrofon")
        case .camera: L("Kamera")
        case .power: L("Strom und Batterie")
        case .audioOutput: L("Audioausgabe")
        case .capsLock: L("Feststelltaste")
        }
    }

    /// Ein Satz für die Einstellungen: Was zeigt die Notch dafür?
    public var explanation: String {
        switch self {
        case .volume: L("Lauter, leiser und stumm, mit Balken.")
        case .brightness: L("Bildschirmhelligkeit, mit Balken.")
        case .keyboardBacklight: L("Tastaturlicht heller und dunkler, mit Balken.")
        case .focus: L("Ein- und ausgeschalteter Fokus, mit Namen und in seiner Farbe.")
        case .timer: L("Laufender Timer aus der Uhr-App mit Restzeit; abgelaufen blinkt er.")
        case .alarm: L("Klingelnder oder schlummernder Wecker aus der Uhr-App.")
        case .microphone: L("Eine App nutzt das Mikrofon; solange bleibt ein oranger Punkt neben der Kamera.")
        case .camera: L("Eine App nutzt die Kamera; solange bleibt ein grüner Punkt neben der Kamera.")
        case .power: L("Netzteil angeschlossen oder entfernt, Batterie fast leer.")
        case .audioOutput: L("Neue Audioausgabe, etwa AirPods oder ein Lautsprecher.")
        case .capsLock: L("Feststelltaste ein und aus.")
        }
    }

    /// Symbol für die Liste in den Einstellungen.
    public var symbol: String {
        switch self {
        case .volume: "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .keyboardBacklight: "keyboard"
        case .focus: "moon.fill"
        case .timer: "timer"
        case .alarm: "alarm.fill"
        case .microphone: "mic.fill"
        case .camera: "video.fill"
        case .power: "battery.100percent.bolt"
        case .audioOutput: "airpodspro"
        case .capsLock: "capslock.fill"
        }
    }

    /// Welche Arten die Dateien der Uhr-App und des Fokus lesen (voller Festplattenzugriff).
    public var needsFullDiskAccess: Bool {
        switch self {
        case .focus, .timer, .alarm: true
        default: false
        }
    }
}

/// Was rechts neben der Kamera steht.
public enum SystemIndicatorValue: Equatable, Sendable {
    /// Balken 0…1.
    case level(Double)
    /// Ein kurzer Text (Fokusname, Gerätename).
    case text(String)
    /// Restzeit, die bis `until` herunterzählt.
    case countdown(until: Date)
    /// Feste Restzeit (pausierter Timer).
    case remaining(TimeInterval)

    /// Texte brauchen mehr Platz als Balken.
    public var isText: Bool {
        if case .level = self { false } else { true }
    }
}

/// Systemfarben wie auf dem iPhone.
public enum SystemTint {
    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let gray = RGB(r: 0.60, g: 0.60, b: 0.63)
    public static let orange = RGB(r: 1.0, g: 0.624, b: 0.039)
    public static let green = RGB(r: 0.188, g: 0.820, b: 0.345)
    public static let red = RGB(r: 1.0, g: 0.271, b: 0.227)
    public static let blue = RGB(r: 0.039, g: 0.518, b: 1.0)
    public static let yellow = RGB(r: 1.0, g: 0.839, b: 0.039)
}

/// Eine Anzeige in der Notch: links das Symbol in seiner Farbe, rechts Balken, Text oder Restzeit.
public struct SystemIndicator: Equatable, Sendable, Identifiable {
    /// Gleiche ID heißt: dieselbe Anzeige wird nur aktualisiert (Lautstärke beim Halten der Taste).
    public var id: String
    public var kind: SystemIndicatorKind
    /// SF-Symbol.
    public var symbol: String
    public var tint: RGB
    public var value: SystemIndicatorValue
    /// Bleibt stehen, bis sie ausdrücklich endet (laufender Timer, klingelnder Wecker).
    public var sticky = false
    /// Blinkt (abgelaufener Timer, klingelnder Wecker).
    public var pulses = false

    public init(id: String? = nil, kind: SystemIndicatorKind, symbol: String, tint: RGB, value: SystemIndicatorValue,
                sticky: Bool = false, pulses: Bool = false) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.symbol = symbol
        self.tint = tint
        self.value = value
        self.sticky = sticky
        self.pulses = pulses
    }

    // MARK: - Lautstärke, Helligkeit, Tastatur

    public static func volume(level: Double, muted: Bool) -> SystemIndicator {
        let clamped = min(max(level, 0), 1)
        let symbol = muted || clamped == 0 ? "speaker.slash.fill"
            : clamped < 0.34 ? "speaker.wave.1.fill" : clamped < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        return SystemIndicator(kind: .volume, symbol: symbol, tint: SystemTint.white, value: .level(muted ? 0 : clamped))
    }

    public static func brightness(level: Double) -> SystemIndicator {
        let clamped = min(max(level, 0), 1)
        return SystemIndicator(kind: .brightness, symbol: clamped < 0.5 ? "sun.min.fill" : "sun.max.fill",
                               tint: SystemTint.white, value: .level(clamped))
    }

    public static func keyboardBacklight(level: Double) -> SystemIndicator {
        SystemIndicator(kind: .keyboardBacklight, symbol: "keyboard", tint: SystemTint.white, value: .level(min(max(level, 0), 1)))
    }

    // MARK: - Fokus

    /// Ein Fokus wurde eingeschaltet: sein Symbol und Name in seiner Farbe.
    public static func focus(_ mode: FocusMode) -> SystemIndicator {
        SystemIndicator(id: "focus", kind: .focus, symbol: mode.symbol, tint: mode.tint, value: .text(mode.name))
    }

    /// Der Fokus wurde ausgeschaltet.
    public static func focusOff(_ mode: FocusMode?) -> SystemIndicator {
        SystemIndicator(id: "focus", kind: .focus, symbol: mode?.symbol ?? "moon.fill", tint: SystemTint.gray,
                        value: .text(L("{0} aus", mode?.name ?? L("Fokus"))))
    }

    // MARK: - Timer und Wecker

    public static func timerRunning(until fireDate: Date) -> SystemIndicator {
        SystemIndicator(kind: .timer, symbol: "timer", tint: SystemTint.orange, value: .countdown(until: fireDate), sticky: true)
    }

    public static func timerPaused(remaining: TimeInterval) -> SystemIndicator {
        SystemIndicator(kind: .timer, symbol: "pause.circle.fill", tint: SystemTint.orange, value: .remaining(remaining), sticky: true)
    }

    /// Abgelaufen: „0:00“ blinkt, bis der Timer in der Uhr-App beendet wird.
    public static func timerFired() -> SystemIndicator {
        SystemIndicator(kind: .timer, symbol: "timer", tint: SystemTint.orange, value: .remaining(0), sticky: true, pulses: true)
    }

    public static func alarmRinging(title: String?) -> SystemIndicator {
        let text = title.flatMap { $0.isEmpty ? nil : $0 } ?? L("Wecker")
        return SystemIndicator(kind: .alarm, symbol: "alarm.fill", tint: SystemTint.orange, value: .text(text), sticky: true, pulses: true)
    }

    public static func alarmSnoozed(until date: Date) -> SystemIndicator {
        SystemIndicator(kind: .alarm, symbol: "zzz", tint: SystemTint.orange, value: .countdown(until: date))
    }

    // MARK: - Mikrofon und Kamera

    public static func microphone(active: Bool) -> SystemIndicator {
        SystemIndicator(kind: .microphone, symbol: active ? "mic.fill" : "mic.slash.fill", tint: active ? SystemTint.orange : SystemTint.gray,
                        value: .text(active ? L("Mikrofon an") : L("Mikrofon aus")))
    }

    public static func camera(active: Bool) -> SystemIndicator {
        SystemIndicator(kind: .camera, symbol: active ? "video.fill" : "video.slash.fill", tint: active ? SystemTint.green : SystemTint.gray,
                        value: .text(active ? L("Kamera an") : L("Kamera aus")))
    }

    // MARK: - Strom

    /// Netzteil angeschlossen (grün mit Blitz) oder entfernt (Batteriesymbol nach Füllstand).
    public static func power(charging: Bool, level: Double?) -> SystemIndicator {
        let level = level.map { min(max($0, 0), 1) }
        if charging {
            return SystemIndicator(kind: .power, symbol: "battery.100percent.bolt", tint: SystemTint.green, value: .level(level ?? 1))
        }
        return SystemIndicator(kind: .power, symbol: batterySymbol(level ?? 1), tint: SystemTint.white, value: .level(level ?? 1))
    }

    /// Batterie fast leer: rot, mit Füllstand.
    public static func lowBattery(level: Double) -> SystemIndicator {
        let clamped = min(max(level, 0), 1)
        return SystemIndicator(id: "power.low", kind: .power, symbol: batterySymbol(clamped), tint: SystemTint.red, value: .level(clamped))
    }

    static func batterySymbol(_ level: Double) -> String {
        switch level {
        case ..<0.125: "battery.0percent"
        case ..<0.375: "battery.25percent"
        case ..<0.625: "battery.50percent"
        case ..<0.875: "battery.75percent"
        default: "battery.100percent"
        }
    }

    // MARK: - Audioausgabe und Feststelltaste

    public static func audioOutput(name: String, symbol: String) -> SystemIndicator {
        SystemIndicator(kind: .audioOutput, symbol: symbol, tint: SystemTint.white, value: .text(name))
    }

    public static func capsLock(on: Bool) -> SystemIndicator {
        SystemIndicator(kind: .capsLock, symbol: on ? "capslock.fill" : "capslock", tint: on ? SystemTint.white : SystemTint.gray,
                        value: .text(on ? L("Feststelltaste an") : L("Feststelltaste aus")))
    }
}

public enum SystemIndicatorFormat {
    /// Restzeit wie in der Uhr-App: „0:07“, „12:34“, „1:02:03“. Nie negativ.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Prozent ohne Nachkommastellen, für Bedienungshilfen.
    public static func percent(_ level: Double) -> String {
        "\(Int((min(max(level, 0), 1) * 100).rounded())) %"
    }
}
