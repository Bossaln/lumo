import Foundation

/// Ein Fokus aus den Systemeinstellungen: Name, SF-Symbol und Farbe, wie Apple sie zeigt.
public struct FocusMode: Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var symbol: String
    public var tint: RGB

    public init(identifier: String, name: String, symbol: String, tint: RGB) {
        self.identifier = identifier
        self.name = name
        self.symbol = symbol
        self.tint = tint
    }
}

/// Farben, die macOS einem Fokus gibt (`tintColorName`), in den Werten der Systemfarben.
public enum FocusTint {
    /// `name` wie in den Dateien von macOS: „indigo“ oder „systemIndigoColor“.
    public static func rgb(named name: String?) -> RGB {
        var key = name?.lowercased() ?? ""
        if key.hasPrefix("system") { key.removeFirst("system".count) }
        if key.hasSuffix("color") { key.removeLast("color".count) }
        return switch key {
        case "red": RGB(r: 1.0, g: 0.271, b: 0.227)
        case "orange": SystemTint.orange
        case "yellow": SystemTint.yellow
        case "green": SystemTint.green
        case "mint": RGB(r: 0.388, g: 0.902, b: 0.886)
        case "teal": RGB(r: 0.251, g: 0.784, b: 0.878)
        case "cyan": RGB(r: 0.353, g: 0.784, b: 0.980)
        case "blue": SystemTint.blue
        case "indigo": RGB(r: 0.369, g: 0.361, b: 0.902)
        case "purple": RGB(r: 0.749, g: 0.353, b: 0.949)
        case "pink": RGB(r: 1.0, g: 0.216, b: 0.373)
        case "brown": RGB(r: 0.675, g: 0.557, b: 0.408)
        case "gray", "grey": SystemTint.gray
        default: RGB(r: 0.369, g: 0.361, b: 0.902)
        }
    }
}

/// Liest die Dateien, in denen macOS Fokus-Einstellungen und den aktiven Fokus führt
/// (`~/Library/DoNotDisturb/DB/ModeConfigurations.json` und `Assertions.json`; dafür braucht lumo vollen
/// Festplattenzugriff). Die Dateien sind verschachteltes JSON; gesucht wird nur, was gebraucht wird, der Rest
/// darf sich ändern.
public struct FocusModes: Equatable, Sendable {
    public var modes: [String: FocusMode]
    /// Kennung des aktiven Fokus; `nil`, wenn keiner an ist.
    public var activeIdentifier: String?

    public var activeMode: FocusMode? {
        activeIdentifier.map { modes[$0] ?? FocusMode(identifier: $0, name: L("Fokus"), symbol: "moon.fill", tint: FocusTint.rgb(named: nil)) }
    }

    public init(modes: [String: FocusMode], activeIdentifier: String?) {
        self.modes = modes
        self.activeIdentifier = activeIdentifier
    }

    public static func parse(configurations: Data, assertions: Data?) -> FocusModes? {
        guard let config = try? JSONSerialization.jsonObject(with: configurations) else { return nil }
        var modes: [String: FocusMode] = [:]
        for dictionary in JSONSearch.dictionaries(named: "modeConfigurations", in: config) {
            for (identifier, value) in dictionary {
                guard let entry = value as? [String: Any], let mode = entry["mode"] as? [String: Any] else { continue }
                // Die Systemfokus stehen englisch in der Datei; lumo benennt sie wie macOS.
                let name = Self.systemName(for: identifier) ?? (mode["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? Self.defaultName(for: identifier)
                modes[identifier] = FocusMode(identifier: identifier, name: name,
                                              symbol: (mode["symbolImageName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "moon.fill",
                                              tint: FocusTint.rgb(named: mode["tintColorName"] as? String))
            }
        }
        var active: String?
        if let assertions, let object = try? JSONSerialization.jsonObject(with: assertions) {
            // Nur die laufenden Zusicherungen (`storeAssertionRecords`) zählen; beendete stehen daneben unter
            // `storeInvalidationRecords` und nennen ihren Fokus genauso. Die jüngste laufende gewinnt.
            var latest: (start: Double, identifier: String)?
            for records in JSONSearch.values(named: "storeAssertionRecords", in: object) {
                for record in (records as? [Any]) ?? [] {
                    let start = JSONSearch.values(named: "assertionStartDateTimestamp", in: record).compactMap { $0 as? Double }.first ?? 0
                    for identifier in JSONSearch.values(named: "assertionDetailsModeIdentifier", in: record).compactMap({ $0 as? String })
                    where latest.map({ start >= $0.start }) ?? true {
                        latest = (start, identifier)
                    }
                }
            }
            active = latest?.identifier
        }
        return FocusModes(modes: modes, activeIdentifier: active)
    }

    /// Fokus, die macOS selbst benennt (in der Datei stehen sie englisch oder leer).
    static func systemName(for identifier: String) -> String? {
        switch identifier {
        case "com.apple.donotdisturb.mode.default": L("Nicht stören")
        case "com.apple.focus.reduce-interruptions": L("Weniger Unterbrechungen")
        default: nil
        }
    }

    /// „Nicht stören“ hat in der Datei keinen Namen; die anderen Standard-Fokus auch nicht immer.
    static func defaultName(for identifier: String) -> String {
        switch identifier {
        case "com.apple.donotdisturb.mode.default": L("Nicht stören")
        case "com.apple.sleep.sleep-mode": L("Schlafen")
        case "com.apple.focus.work": L("Arbeiten")
        case "com.apple.focus.personal-time": L("Persönlich")
        case "com.apple.focus.driving": L("Fahren")
        case "com.apple.focus.fitness": L("Fitness")
        case "com.apple.focus.gaming": L("Spielen")
        case "com.apple.focus.mindfulness": L("Achtsamkeit")
        case "com.apple.focus.reading": L("Lesen")
        default: L("Fokus")
        }
    }
}

/// Sucht in beliebig verschachteltem JSON nach Schlüsseln.
enum JSONSearch {
    static func values(named key: String, in object: Any) -> [Any] {
        var found: [Any] = []
        func walk(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                if let value = dictionary[key] { found.append(value) }
                for value in dictionary.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(object)
        return found
    }

    static func dictionaries(named key: String, in object: Any) -> [[String: Any]] {
        values(named: key, in: object).compactMap { $0 as? [String: Any] }
    }
}
