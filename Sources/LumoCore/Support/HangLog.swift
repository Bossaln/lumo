import Foundation

/// Merkt sich, wann lumo nicht sofort reagiert hat: Der Haupt-Thread kam erst nach `threshold` oder später
/// dazu, eine Nachricht zu bearbeiten (Menüleiste, Notch, Einstellungen). Gemessen wird nur mit eingeschalteten
/// Entwickleroptionen; die Seite „Entwickler“ zeigt die Liste.
public struct HangLog: Sendable {
    public struct Entry: Equatable, Sendable {
        public var at: Date
        public var milliseconds: Int
        /// Was gerade los war (Notch-Zustand, Musik, offene Fenster).
        public var context: String
    }

    /// Ab dieser Verzögerung spürt man es beim Klicken.
    public static let threshold: TimeInterval = 0.1
    public static let keep = 20

    /// Neueste zuerst.
    public private(set) var entries: [Entry] = []
    public private(set) var count = 0
    public private(set) var longestMilliseconds = 0

    public init() {}

    /// Trägt eine Verzögerung ein, wenn sie spürbar war; `true`, wenn sie eingetragen wurde.
    @discardableResult
    public mutating func record(delay: TimeInterval, at date: Date, context: String) -> Bool {
        guard delay >= Self.threshold else { return false }
        let milliseconds = Int((delay * 1000).rounded())
        entries.insert(Entry(at: date, milliseconds: milliseconds, context: context), at: 0)
        if entries.count > Self.keep { entries.removeLast(entries.count - Self.keep) }
        count += 1
        longestMilliseconds = max(longestMilliseconds, milliseconds)
        return true
    }

    public var summary: String {
        switch count {
        case 0: L("Keine Hänger gemessen")
        case 1: L("1 Hänger, längster {0} ms", longestMilliseconds)
        default: L("{0} Hänger, längster {1} ms", count, longestMilliseconds)
        }
    }

    /// Zum Kopieren: Zusammenfassung und je Hänger Uhrzeit, Dauer und was gerade los war.
    public func report(timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let lines = entries.map { entry in
            let time = calendar.dateComponents([.hour, .minute, .second], from: entry.at)
            let clock = String(format: "%02d:%02d:%02d", time.hour ?? 0, time.minute ?? 0, time.second ?? 0)
            return "\(clock)  \(entry.milliseconds) ms  \(entry.context)"
        }
        return ([summary] + lines).joined(separator: "\n")
    }
}
